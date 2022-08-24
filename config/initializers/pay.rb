Rails.application.config.to_prepare do
  Pay::FakeProcessor::Billable.module_eval do 
    # Little hack to prevent the `processor_id` from being overriden
    def subscribe(name: Pay.default_product_name, plan: Pay.default_plan_name, **options)
      # Make to generate a processor_id
      customer
      attributes = options.merge(
        name: name,
        processor_plan: plan,
        status: :active,
        quantity: options.fetch(:quantity, 1)
      ).reverse_merge(processor_id: SecureRandom.uuid)

      if (trial_period_days = attributes.delete(:trial_period_days))
        attributes[:trial_ends_at] = trial_period_days.to_i.days.from_now
      end

      pay_customer.subscriptions.create!(attributes)
    end
  end
end
