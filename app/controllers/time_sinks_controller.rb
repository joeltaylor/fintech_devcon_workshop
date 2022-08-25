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
