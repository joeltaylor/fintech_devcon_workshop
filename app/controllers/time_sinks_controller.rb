class TimeSinksController < ApplicationController
  def create
    flash[:notice] = "The silicon has determined you will wait for #{rand(100)} minutes!"
    redirect_to root_path
  end
end
