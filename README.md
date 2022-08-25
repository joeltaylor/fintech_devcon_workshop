# Steps
## Initial setup
```
# Install gems
bundle install

# Setup databse
bin/rails db:setup

# Start the server
bin/rails server
```

## Scaffold the base resources
The [pay](https://github.com/pay-rails/pay) gem such a neat project that I couldn't help myself but integrate it into this example. Out of the box, it provides the necessary resources (`Customer`, `PaymentMethod`, `Subscriptions`, `Charges`, `Webhooks`) to lay the foundation for a payment system. 

**This application is severely misusing the gem** because it is designed to leverage the subscription functionality of the PSP. I've mangled the `FakeProcessor` to allow us to loosely take advantage of the domain model and hand wave over actually integrating with a PSP. 

💡**Centering payment domain objects around a Customer is great for avoiding direct coupling to Users. This become even more invaluable the moment your application needs more than Users (e.g., teams or organizations)**

💡**When possible, it's best to decouple your integration from your PSP. Modeling your system around your PSP reduces flexibility and makes it challenging to juggle your domain with their domain**

💡**Async webhook processing is a great safety net especially if the PSP doesn't provide reliable retries**

## Lago setup

### Installation
Let's get a self hosted version of Lago up and running locally:

```
# Get the code
git clone https://github.com/getlago/lago.git

# Go to Lago folder
cd lago

# Set up environment configuration
echo "LAGO_RSA_PRIVATE_KEY=\"`openssl genrsa 2048 | base64`\"" >> .env
source .env

# Start
docker-compose up
```

### Sign up
Head over to [http://localhost](http://localhost)and sign up for an account. 

<img width="938" alt="Screen Shot 2022-08-24 at 8 00 46 PM" src="https://user-images.githubusercontent.com/6965062/186731082-b9b1a3a8-0286-459d-b03f-f7130f57c633.png">


## Add billable metric
Our application is going to bill customers by the minute. Lago [handles the aggregation](https://doc.getlago.com/docs/guide/billable-metrics/aggregation-types) for us and all we need to do is configure it. Click "Billable metrics" then "Add a billable metric" and fill in using the data below

<img width="809" alt="Screen Shot 2022-08-24 at 8 08 10 PM" src="https://user-images.githubusercontent.com/6965062/186731133-7f40197a-8d00-4951-aaee-3430412ed9a2.png">

### Plan creation
Click "Plans" and then "Add a plan". We're going to be creating two plans: monthly and yearly. Both plans will be paid in advance and then the metered usage will be billed in arrears based on consumption using a tiered pricing model.

**Monthly**

<img width="436" alt="Screen Shot 2022-08-24 at 8 12 12 PM" src="https://user-images.githubusercontent.com/6965062/186731190-090420e4-3486-469b-8255-a95de5fcbac0.png">

**Yearly**
The major difference with the yearly plan is that we select the "Apply charges monthly" toggle. This will make it so that the customer is billed yearly for their plan, but then monthly for any usage that exceeds their free tier. Otherwise, we'd have to wait a year before getting paid.

<img width="399" alt="Screen Shot 2022-08-24 at 8 18 23 PM" src="https://user-images.githubusercontent.com/6965062/186731265-ffe37e3d-39d6-4146-a84a-e8c4f526b21a.png">

## Sending customer data to Lago
Now that we've got the plans configured it's time to integrate the application. We're going to use our imagination and pretend the customer and payment method are magically being created as part of the subscription flow. To set the customer up in Lago we need to add the SDK and write some code:

**Add the gem as a dependency**
```
./bin/bundle add lago-ruby-client

bundle install
```

**Fetch your API key from Lago (Developers -> API keys) and store in in `.env`**
```
cp .env.template .env

# update LAGO_API_KEY
```

**Setup the client**
```
# Within config/application.rb add the following within the `PayToWait` module

  def self.lago_client
    @lago_client ||= ::Lago::Api::Client.new(api_key: ENV['LAGO_API_KEY'], api_url: ENV['LAGO_URL'])
  end

```
**Create a background job that creates the customer and subscribes them to the correct plan.**
In the spirit of handling the customer setup asynchronously, we'll create a background job and default to giving the customer immediate access to the product. We haven't set up a real queue adapter, but the code is same nonetheless.

```
# Generate the job as if it were to be queued as the most important

bin/rails generate job sync_lago_cutomer --queue urgent
```

Add the following code to `app/jobs/sync_lago_customer.rb`

```
class SyncLagoCutomerJob < ApplicationJob
  queue_as :urgent

  def perform(user_id:, plan_code:)
    user = User.find(user_id)

    # /api/v1/customers will act as an update if the customer already exists. If this were
    # not an internal application, we'd want to pass a UUID instead of the primary key.
    PayToWait.lago_client.customers.create(customer_id: user_id, name: user.name)

    # Defaulting to calendar billing. Lago will automatically handle prorations based on the
    # date the subscription starts. We have the option to pass an idempotency key, which
    # is something we'd want to add.
    subscription = PayToWait.lago_client.subscriptions.create(customer_id: user_id.to_s, plan_code: plan_code)

    # Again – this is using functionality from the pay gem in an incorrect way, but it's still "working"
    # for this example
    user.payment_processor.subscribe(name: "default", plan: plan_code, processor_id: subscription.lago_id, processor_plan: plan_code)

  end
end

```

Update the `app/controller/subscriptions_controller.rb` to enqueue our job

```
class SubscriptionsController < ApplicationController
  def create
    # This is mostly for demonstration purchases. In addition to pre-authing, we could set a temporary
    # trial subscription that has safe guarded limitations that aren't immediately visible to the user.
    # current_user.payment_processor.subscribe(trial_ends_at: 10.minutes.from_now, ends_at: 10.minutes.from_now)

    SyncLagoCutomerJob.perform_later(user_id: current_user.id, plan_code: params[:plan_code])

    flash[:notice] = "You're subscribed!"
    redirect_to root_path
  end
end

```

## Charge for the subscription
Lago can be configured to send webhooks to any destination we want. A full list of the webhooks they send can be found in their [documentation](https://doc.getlago.com/docs/api/webhooks/messages). For this portion, we will create a webhook endpoint, persist them to our DB, and queue them up for processing. 

**Configure the webhooks endpoint in Lago**
Head over to http://localhost -> Developers -> Webooks and add the following endpoint: `http://host.docker.internal:3001/webhooks/lago`

**Create controller and model**
```
# Create the controller
bin/rails g controller webhooks/lago

# Create model to persist the webhooks
rails g model webhooks type:string data:json

# Add webhook verification dependency
./bin/bundle add jwt

bundle install

bin/rails db:migrate
```

Within the controller, we want to validate that the webhook is from Lago. We'll need to fetch the public key in order to do this, which we can do when our application boots so we aren't fetching it for every single webhook.

```
# config/application.rb

  def self.lago_public_key
    return @webhooks_public_key if defined?(@webhooks_public_key)

    require 'net/http'

    uri = URI("#{ENV['LAGO_URL']}/api/v1/webhooks/public_key")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == "https"

    response = http.send_request(
      'GET',
      uri.request_uri,
      '',
      { 'Authorization' => "Bearer #{ENV['LAGO_API_KEY']}" }
    )

    @webhooks_public_key = response.body
  end
```

Next, we'll add code to our controller to check the signature, create a webhook record, and enqueue an event:

```
# app/controllers/webhooks/lago_controller.rb

require 'openssl'
require 'jwt'

class Webhooks::LagoController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def create
    if queue_valid_event
      head :ok
    else
      head :bad_request
    end
  end

  private

  def queue_valid_event
    payload = request.body.read

    decoded_signature = JWT.decode(
      request.headers['X-Lago-Signature'],
      OpenSSL::PKey::RSA.new(Base64.decode64(PayToWait.lago_public_key)),
      true,
      {
        algorithm: 'RS256',
        iss: ENV['LAGO_URL'],
        verify_iss: true,
      },
    ).first

    return false unless decoded_signature['data'] == payload
    webhook = Webhook.create(event_type: params['webhook_type'], data: JSON.parse(payload))
    LagoWebhookJob.perform_later(webhook.id)
  end
end
```

The `config/routes.rb` file will also need to be update with the new endpoint by adding:
```
post 'webhooks/lago', to: 'webhooks/lago#create'
```

**Job to process invoice.created webhook and charge customer **

Now it's time to make some money move! We're defaulting to storing all webhook events but that need will likely vary from application to application. I like to listen to any event that has to do with payment methods, charges, failures, account modification, etc. even if I don't do anything with them so I can add monitoring around them. 

💡**Monitoring webhooks can be a great first indicator to detect anomalous behavior or regressions – it can also make for a noisy on-call shift if over done.**

```
# Create the worker
bin/rails g job LagoWebhookJob
```

Now we can charge and update the status of the invoice:

```
# app/jobs/lago_webhook_job.rb

class LagoWebhookJob < ApplicationJob
  queue_as :default

  def perform(webhook_id)
    webhook = Webhook.find(webhook_id)

    # For the sake of brevity, we'll only process the invoice.created webhook. We'll code everything
    # in this job, but we'd probably want to split out the processing logic into separate classes
    # per event.
    return unless webhook.event_type == "invoice.created"

    invoice_id = webhook.data.dig("invoice", "lago_id")
    customer_id = webhook.data.dig("invoice", "customer", "customer_id")
    amount_to_charge = webhook.data.dig("invoice", "total_amount_cents")
    user = User.find(customer_id)

    # Will raise a Pay::Error on failure. Chances are we'll want to have a limited number of retries
    # with a bit of delay to avoid intermittent failures. Not all failures are equal and it'd be worth
    # the time to understand what error codes your payment processor makes available so you can choose
    # how to handle them. For now, we'll let the error bubble up and halt progress.
    #
    # It's critical to understand how the processor you're working with deals with idempotency.
    # If it's supported, I like to pass the invoice or transaction ID as the idempotency key.
    user.payment_processor.charge(amount_to_charge)

    # Would be better to queue this up, but for demonstration we'll update the status of
    # the invoice synchronously.
    PayToWait.lago_client.invoices.update({status: "succeeded"}, invoice_id)
  end
end

```

## Emit events
The final step! Now we want to emit usage events so that we can charge the user. For this example, we're going to simulate an external service that sends events to our Lago instance.

```
# app/controllers/time_sinks_controller.rb

class TimeSinksController < ApplicationController
  def create
    # We're going to simulate a service that sends events based on usage. This is a convenience
    # for demonstration.
    time_to_wait = rand(100)
    flash[:notice] = "The silicon has determined you will wait for #{time_to_wait} minutes!"

    PayToWait.lago_client.events.create(
      transaction_id: "#{Time.now.to_i}-#{current_user.id}",
      customer_id: current_user.id,
      code: "sum_minutes",
      timestamp: Time.now.to_i,
      properties: { minutes: time_to_wait}
    )

    redirect_to root_path
  end
end

```

To explore how future invoicing works, we do a bit of time travel:
```
subs = Subscription.find('YOUR_SUB_ID')
date = DateTime.parse('2022-08-24')
BillSubscriptionJob.perform_later([subs], date)
```
