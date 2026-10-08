class FeedbackTargetsController < ApplicationController
  before_action :set_today

  def new
    @feedback_target = FeedbackTarget.find_by(target_date: @target_date) || FeedbackTarget.new(target_date: @target_date)
    load_dishes
  end

  def create
    @feedback_target = FeedbackTarget.find_by(target_date: @target_date)
    return render :new if @feedback_target

    @feedback_target = FeedbackTarget.new(feedback_target_params.merge(target_date: @target_date))

    if @feedback_target.save
      redirect_to root_path, status: :see_other
    else
      @feedback_target = FeedbackTarget.find_by(target_date: @target_date) || @feedback_target
      load_dishes
      render :new, status: @feedback_target.persisted? ? :ok : :unprocessable_content
    end
  rescue ActiveRecord::RecordNotUnique
    @feedback_target = FeedbackTarget.find_by!(target_date: @target_date)
    render :new
  end

  private

  def set_today
    @target_date = Date.current
  end

  def load_dishes
    @dishes = Dish.order(:name, :category) unless @feedback_target.persisted?
  end

  def feedback_target_params
    params.require(:feedback_target).permit(:dish_id)
  end
end
