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
