class ReactionsController < ApplicationController
  before_action :require_kindergarten_user
  before_action :load_target
  before_action :load_entry, only: [ :new, :create ]

  def index
    @reaction_summary = @feedback_target&.reaction_summary
  end

  def new
    @selected_classroom = @classrooms.find { |classroom| classroom.id.to_s == params[:classroom_id] }
    @reaction = if @selected_classroom && @feedback_target
      @selected_classroom.reactions.find_by(feedback_target: @feedback_target)
    end
    @reaction ||= initial_reaction
    if @reaction.persisted?
      snapshot = ReactionSubmission.edit_snapshot(reaction: @reaction, target_snapshot: target_snapshot)
      @displayed_reaction = Rails.application.message_verifier(:reaction_edit).generate(snapshot)
    end
  end

  def create
    attributes = reaction_params
    @reaction = Reaction.new(attributes)
    @selected_classroom = @classrooms.find { |classroom| classroom.id.to_s == params[:classroom_id] }
    @reaction.classroom = @selected_classroom
    @reaction.feedback_target = @feedback_target

    unless @feedback_target
      @reaction.errors.add(:base, "本日のフィードバック対象料理はまだ設定されていません。")
      return render :new, status: :unprocessable_content
    end

    unless displayed_target_current?
      return render_stale_entry
    end

    unless @selected_classroom
      @reaction.errors.add(:base, "担当クラスを選択してください。")
      return render :new, status: :unprocessable_content
    end

    submission = ReactionSubmission.call(reaction: @reaction, attributes: attributes,
      displayed_reaction: params[:displayed_reaction], target_snapshot: target_snapshot)
    @reaction = submission.reaction
    @displayed_reaction = params[:displayed_reaction] if @reaction.persisted?

    case submission.status
    when :created, :updated
      notice = submission.status == :updated ? "登録内容を更新しました" : "登録が成功しました"
      redirect_to reactions_path, notice: notice, status: :see_other
    when :invalid
      render :new, status: :unprocessable_content
    when :stale
      render_stale_entry
    when :already_registered
      render_already_registered
    end
  end

  private

  def load_target
    @target_date = Date.current
    @feedback_target = FeedbackTarget.find_by(target_date: @target_date)
    @dish = @feedback_target&.dish
  end

  def load_entry
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

  def render_stale_entry
    @reaction = initial_reaction
    @selected_classroom = nil
    @reaction.errors.add(:base, "対象日または対象料理が変更されています。最新の情報を確認し、再入力してください。")
    render :new, status: :unprocessable_content
  end

  def render_already_registered
    @reaction.errors.clear
    @reaction.errors.add(:base, "このクラスの本日のリアクションは登録済みです。")
    render :new, status: :unprocessable_content
  end

  def reaction_params
    counts = params.fetch(:reaction, ActionController::Parameters.new).permit(:positive_count, :neutral_count, :negative_count)
    %i[ positive_count neutral_count negative_count ].index_with { |attribute| counts[attribute] }
  end
end
