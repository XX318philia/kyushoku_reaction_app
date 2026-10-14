class ReactionSubmission
  Result = Data.define(:status, :reaction)

  def self.call(reaction:, attributes:, displayed_reaction:, target_snapshot:)
    new(reaction: reaction, attributes: attributes, displayed_reaction: displayed_reaction,
      target_snapshot: target_snapshot).call
  end

  def self.edit_snapshot(reaction:, target_snapshot:)
    [ target_snapshot, reaction.classroom_id, reaction.id ]
  end

  def initialize(reaction:, attributes:, displayed_reaction:, target_snapshot:)
    @reaction = reaction
    @attributes = attributes
    @displayed_reaction = displayed_reaction
    @target_snapshot = target_snapshot
  end

  def call
    existing = existing_reaction
    if @displayed_reaction.present?
      return result(:stale) unless existing && editing_signature_valid?(existing)

      @reaction = existing
      @reaction.assign_attributes(@attributes)
    elsif existing
      return result(:already_registered)
    end

    save_reaction
  end

  private

  def existing_reaction
    @reaction.classroom.reactions.find_by(feedback_target: @reaction.feedback_target)
  end

  def editing_signature_valid?(reaction)
    @displayed_reaction.is_a?(String) &&
      Rails.application.message_verifier(:reaction_edit).verified(@displayed_reaction) ==
        self.class.edit_snapshot(reaction: reaction, target_snapshot: @target_snapshot)
  end

  def save_reaction
    updating = @reaction.persisted?
    if @reaction.save
      result(updating ? :updated : :created)
    elsif @reaction.errors.of_kind?(:classroom_id, :taken)
      result(:already_registered)
    else
      result(:invalid)
    end
  rescue ActiveRecord::RecordNotUnique
    result(:already_registered)
  end

  def result(status)
    Result.new(status: status, reaction: @reaction)
  end
end
