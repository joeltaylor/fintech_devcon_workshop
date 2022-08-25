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
