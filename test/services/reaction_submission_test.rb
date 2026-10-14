require "test_helper"

class ReactionSubmissionTest < ActiveSupport::TestCase
  setup do
    @classroom = FactoryBot.create(:classroom)
    @feedback_target = FactoryBot.create(:feedback_target)
    @attributes = { positive_count: "12", neutral_count: "3", negative_count: "1" }
    @reaction = Reaction.new(@attributes.merge(classroom: @classroom, feedback_target: @feedback_target))
    @target_snapshot = target_snapshot(@feedback_target)
  end

  test "edit snapshot preserves the original target classroom and reaction data" do
    reaction = saved_reaction

    assert_equal [ [ @feedback_target.target_date.iso8601, @feedback_target.id, @feedback_target.dish_id ],
      @classroom.id, reaction.id ],
      ReactionSubmission.edit_snapshot(reaction: reaction, target_snapshot: @target_snapshot)
  end

  test "creates one reaction and returns the saved reaction" do
    result = nil

    assert_difference "Reaction.count", 1 do
      result = submit
    end

    assert_equal :created, result.status
    assert_same @reaction, result.reaction
    assert result.reaction.persisted?
    assert_equal @classroom.id, result.reaction.classroom_id
    assert_equal @feedback_target.id, result.reaction.feedback_target_id
    assert_equal [ 12, 3, 1 ], result.reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
  end

  test "updates an existing reaction with an original format signature and preserves its id and created timestamp" do
    reaction = saved_reaction
    original_id = reaction.id
    original_created_at = reaction.created_at
    result = nil

    assert_no_difference "Reaction.count" do
      result = submit(displayed_reaction: editing_signature(reaction))
    end

    assert_equal :updated, result.status
    assert result.reaction.persisted?
    assert_equal original_id, result.reaction.id
    assert_equal original_created_at, result.reaction.created_at
    assert_equal @classroom.id, result.reaction.classroom_id
    assert_equal @feedback_target.id, result.reaction.feedback_target_id
    assert_equal [ 12, 3, 1 ], reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
  end

  test "does not save invalid registration and returns the input and model errors" do
    @attributes[:positive_count] = "-1"
    @reaction.assign_attributes(@attributes)
    result = nil

    assert_no_difference "Reaction.count" do
      result = submit
    end

    assert_equal :invalid, result.status
    assert_same @reaction, result.reaction
    assert_not result.reaction.persisted?
    assert_equal "-1", result.reaction.positive_count_before_type_cast
    assert result.reaction.errors.of_kind?(:positive_count, :greater_than_or_equal_to)
  end

  test "invalid updates preserve saved data and return the persisted editing state with inputs and model errors" do
    reaction = saved_reaction
    original_attributes = reaction.attributes
    @attributes[:positive_count] = "1.5"
    result = nil

    assert_no_difference "Reaction.count" do
      result = submit(displayed_reaction: editing_signature(reaction))
    end

    assert_equal :invalid, result.status
    assert result.reaction.persisted?
    assert_equal reaction.id, result.reaction.id
    assert_equal reaction.created_at, result.reaction.created_at
    assert_equal [ "1.5", "3", "1" ],
      %i[ positive_count neutral_count negative_count ].map { |attribute| result.reaction.public_send("#{attribute}_before_type_cast") }
    assert result.reaction.errors.of_kind?(:positive_count, :not_an_integer)
    assert_equal original_attributes, reaction.reload.attributes
  end

  test "rejects invalid tampered nonstring and wrong verifier editing signatures without changing saved data" do
    reaction = saved_reaction
    original_attributes = reaction.attributes
    token = editing_signature(reaction)
    entry_token = Rails.application.message_verifier(:reaction_entry).generate([ @target_snapshot, reaction.classroom_id, reaction.id ])

    [ "invalid", "#{token}tampered", [ token ], { token: token }, entry_token ].each do |signature|
      result = nil

      assert_no_difference "Reaction.count" do
        result = submit(displayed_reaction: signature)
      end

      assert_equal :stale, result.status
      assert_same @reaction, result.reaction
      assert_equal original_attributes, reaction.reload.attributes
    end
  end

  test "rejects editing signatures for another class or target without changing any records" do
    reaction = saved_reaction
    other_classroom = FactoryBot.create(:classroom, kindergarten: @classroom.kindergarten)
    other_classroom_reaction = saved_reaction(classroom: other_classroom)
    other_target = FactoryBot.create(:feedback_target, dish: @feedback_target.dish)
    other_target_reaction = saved_reaction(target: other_target)
    records = [ reaction, other_classroom_reaction, other_target_reaction ]
    original_attributes = records.map(&:attributes)

    [ other_classroom_reaction, other_target_reaction ].each do |other_reaction|
      result = nil

      assert_no_difference "Reaction.count" do
        result = submit(displayed_reaction: editing_signature(other_reaction))
      end

      assert_equal :stale, result.status
      assert_equal original_attributes, records.map { |record| record.reload.attributes }
    end
  end

  test "does not register a replacement when an editing signature has no existing reaction" do
    reaction = saved_reaction
    token = editing_signature(reaction)
    reaction.destroy!
    result = nil

    assert_no_difference "Reaction.count" do
      result = submit(displayed_reaction: token)
    end

    assert_equal :stale, result.status
    assert_not result.reaction.persisted?
  end

  test "missing and blank editing signatures cannot overwrite an existing reaction" do
    reaction = saved_reaction
    original_attributes = reaction.attributes

    [ nil, "", "   " ].each do |signature|
      result = nil

      assert_no_difference "Reaction.count" do
        result = submit(displayed_reaction: signature)
      end

      assert_equal :already_registered, result.status
      assert_same @reaction, result.reaction
      assert_not result.reaction.persisted?
      assert_equal original_attributes, reaction.reload.attributes
    end
  end

  test "blank editing signatures allow registration when no record exists" do
    [ "", "   " ].each do |signature|
      classroom = FactoryBot.create(:classroom, kindergarten: @classroom.kindergarten)
      reaction = Reaction.new(@attributes.merge(classroom: classroom, feedback_target: @feedback_target))
      result = nil

      assert_difference "Reaction.count", 1 do
        result = submit(reaction: reaction, displayed_reaction: signature)
      end

      assert_equal :created, result.status
      assert_same reaction, result.reaction
      assert result.reaction.persisted?
    end
  end

  test "model uniqueness validation returns already registered and preserves the competing record" do
    assert_competing_submission(validate: true)
  end

  test "a database uniqueness conflict returns already registered and preserves the competing record" do
    assert_competing_submission(validate: false)
  end

  private

  def submit(reaction: @reaction, displayed_reaction: nil)
    ReactionSubmission.call(reaction: reaction, attributes: @attributes,
      displayed_reaction: displayed_reaction, target_snapshot: @target_snapshot)
  end

  def saved_reaction(classroom: @classroom, target: @feedback_target)
    FactoryBot.create(:reaction, classroom: classroom, feedback_target: target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
  end

  def target_snapshot(target)
    [ target.target_date.iso8601, target.id, target.dish_id ]
  end

  def editing_signature(reaction)
    # 従来のControllerと同じ元データで生成し、署名の互換性を検証する。
    Rails.application.message_verifier(:reaction_edit).generate([ target_snapshot(reaction.feedback_target), reaction.classroom_id, reaction.id ])
  end

  def assert_competing_submission(validate:)
    first_reaction = @reaction.dup
    first_reaction.assign_attributes(positive_count: 2, neutral_count: 1, negative_count: 0)
    @reaction.define_singleton_method(:save) do
      first_reaction.save!
      # 実際のDB競合はsavepoint内で起こし、テスト全体のtransactionを保護する。
      Reaction.transaction(requires_new: true) { super(validate: validate) }
    end
    result = nil

    assert_difference "Reaction.count", 1 do
      result = submit
    end

    assert_equal :already_registered, result.status
    assert_same @reaction, result.reaction
    assert_not result.reaction.persisted?
    assert first_reaction.persisted?
    assert_equal first_reaction, Reaction.find_by!(classroom: @classroom, feedback_target: @feedback_target)
    assert_equal [ 2, 1, 0 ], first_reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
  end
end
