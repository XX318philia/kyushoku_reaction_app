class ReactionsController < ApplicationController
  before_action :require_kindergarten_user
  before_action :load_entry

  def new
    @selected_classroom = @classrooms.find { |classroom| classroom.id.to_s == params[:classroom_id] }
    @reaction = if @selected_classroom && @feedback_target
      @selected_classroom.reactions.find_by(feedback_target: @feedback_target)
    end
    @reaction ||= initial_reaction
  end

  def create
    @reaction = Reaction.new(reaction_params)
    @selected_classroom = @classrooms.find { |classroom| classroom.id.to_s == params[:classroom_id] }
    @reaction.classroom = @selected_classroom
    @reaction.feedback_target = @feedback_target

    unless @feedback_target
      @reaction.errors.add(:base, "本日のフィードバック対象料理はまだ設定されていません。")
      return render :new, status: :unprocessable_content
    end

    unless displayed_target_current?
      @reaction = initial_reaction
      @selected_classroom = nil
      @reaction.errors.add(:base, "対象日または対象料理が変更されています。最新の情報を確認し、再入力してください。")
      return render :new, status: :unprocessable_content
    end

    unless @selected_classroom
      @reaction.errors.add(:base, "担当クラスを選択してください。")
      return render :new, status: :unprocessable_content
    end

    return render_already_registered if Reaction.exists?(classroom: @selected_classroom, feedback_target: @feedback_target)

    if @reaction.save
      redirect_to new_reaction_path, notice: "登録が成功しました", status: :see_other
    elsif @reaction.errors.of_kind?(:classroom_id, :taken)
      render_already_registered
    else
      render :new, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotUnique
    render_already_registered
  end

  private

  def load_entry
    @target_date = Date.current
    @feedback_target = FeedbackTarget.find_by(target_date: @target_date)
    @dish = @feedback_target&.dish
    @classrooms = current_user.kindergarten.classrooms
    @displayed_target = Rails.application.message_verifier(:reaction_entry).generate(target_snapshot) if @feedback_target
  end

  def initial_reaction
    Reaction.new(positive_count: 0, neutral_count: 0, negative_count: 0)
  end

  def target_snapshot
    [ @target_date.iso8601, @feedback_target.id, @feedback_target.dish_id ]
  end

  def displayed_target_current?
    token = params[:displayed_target]
    token.is_a?(String) && Rails.application.message_verifier(:reaction_entry).verified(token) == target_snapshot
  end

  def render_already_registered
    @reaction.errors.clear
    @reaction.errors.add(:base, "このクラスの本日のリアクションは登録済みです。")
    render :new, status: :unprocessable_content
  end

  def reaction_params
    params.fetch(:reaction, ActionController::Parameters.new).permit(:positive_count, :neutral_count, :negative_count)
  end

  def require_kindergarten_user
    return redirect_to kindergarten_login_path unless logged_in?

    head :forbidden unless kindergarten_user?
  end
end
