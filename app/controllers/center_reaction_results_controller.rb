class CenterReactionResultsController < ApplicationController
  before_action :require_center_user

  def index
    @target_date = Date.current
    @feedback_target = FeedbackTarget.find_by(target_date: @target_date)
    @dish = @feedback_target&.dish
    @reaction_summary = @feedback_target&.reaction_summary
  end

  private

  def require_center_user
    return redirect_to center_login_path unless logged_in?

    head :forbidden unless center_user?
  end
end
