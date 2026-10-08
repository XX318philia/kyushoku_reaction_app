class ReactionsController < ApplicationController
  before_action :require_kindergarten_user

  def new
    @target_date = Date.current
    @dish = FeedbackTarget.find_by(target_date: @target_date)&.dish
    @classrooms = current_user.kindergarten.classrooms
  end

  private

  def require_kindergarten_user
    return redirect_to kindergarten_login_path unless logged_in?

    head :forbidden unless kindergarten_user?
  end
end
