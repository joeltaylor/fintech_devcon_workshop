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
