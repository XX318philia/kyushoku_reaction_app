class FeedbackTargetsController < ApplicationController
  before_action :require_center_user
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
      redirect_to center_reaction_results_path, status: :see_other
    else
      @feedback_target = FeedbackTarget.find_by(target_date: @target_date) || @feedback_target
      load_dishes
      render :new, status: @feedback_target.persisted? ? :ok : :unprocessable_content
    end
  rescue ActiveRecord::RecordNotUnique
    @feedback_target = FeedbackTarget.find_by!(target_date: @target_date)
    render :new
  end

  def confirm_destroy
    @feedback_target = FeedbackTarget.find_by(target_date: @target_date)
    return redirect_stale_confirmation unless @feedback_target && params[:id] == @feedback_target.id.to_s

    @displayed_target = cancellation_verifier.generate(target_snapshot)
  end

  def destroy
    result = FeedbackTarget.transaction do
      @feedback_target = FeedbackTarget.lock.find_by(target_date: @target_date)

      if !displayed_target_current?
        :stale
      elsif @feedback_target.destroy
        :destroyed
      else
        raise ActiveRecord::Rollback
      end
    end

    case result
    when :destroyed
      redirect_to new_feedback_target_path, notice: "本日の対象料理を取り消しました", status: :see_other
    when :stale
      redirect_stale_confirmation
    else
      redirect_cancellation_failure
    end
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::StatementInvalid
    redirect_cancellation_failure
  end

  private

  def cancellation_verifier
    Rails.application.message_verifier(:feedback_target_cancellation)
  end

  def target_snapshot
    [ @target_date.iso8601, @feedback_target.id, @feedback_target.dish_id ]
  end

  def displayed_target_current?
    token = params[:displayed_target]
    @feedback_target && params[:id] == @feedback_target.id.to_s && token.is_a?(String) &&
      cancellation_verifier.verified(token) == target_snapshot
  end

  def redirect_stale_confirmation
    redirect_to new_feedback_target_path,
      alert: "本日の対象料理の設定が変更されたため、取り消せませんでした。最新の設定を確認してください。", status: :see_other
  end

  def redirect_cancellation_failure
    redirect_to new_feedback_target_path, alert: "取り消しに失敗しました", status: :see_other
  end

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
