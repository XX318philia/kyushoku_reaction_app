require "test_helper"

class ReactionTest < ActiveSupport::TestCase
  setup do
    kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    @classroom = Classroom.create!(kindergarten: kindergarten, name: "ひまわり組")
    dish = Dish.create!(name: "野菜スープ", category: :soup)
    @feedback_target = FeedbackTarget.create!(dish: dish, target_date: Date.new(2026, 10, 8))
    @reaction = Reaction.new(classroom: @classroom, feedback_target: @feedback_target,
      positive_count: 10, neutral_count: 5, negative_count: 2)
  end

  test "saves a reaction with associations counts and timestamps" do
    assert @reaction.save
    @reaction.reload

    assert_equal @classroom.id, @reaction.classroom_id
    assert_equal @classroom, @reaction.classroom
    assert_equal @feedback_target.id, @reaction.feedback_target_id
    assert_equal @feedback_target, @reaction.feedback_target
    assert_equal 10, @reaction.positive_count
    assert_equal 5, @reaction.neutral_count
    assert_equal 2, @reaction.negative_count
    assert_not_nil @reaction.created_at
    assert_not_nil @reaction.updated_at
  end

  test "does not save without a classroom" do
    @reaction.classroom = nil

    assert_not @reaction.save
    assert @reaction.errors.of_kind?(:classroom, :blank)
  end

  test "does not save with a nonexistent classroom" do
    @reaction.classroom_id = Classroom.maximum(:id) + 1

    assert_not @reaction.save
    assert @reaction.errors.of_kind?(:classroom, :blank)
  end

  test "does not save without a feedback target" do
    @reaction.feedback_target = nil

    assert_not @reaction.save
    assert @reaction.errors.of_kind?(:feedback_target, :blank)
  end

  test "does not save with a nonexistent feedback target" do
    @reaction.feedback_target_id = FeedbackTarget.maximum(:id) + 1

    assert_not @reaction.save
    assert @reaction.errors.of_kind?(:feedback_target, :blank)
  end

  [ :positive_count, :neutral_count, :negative_count ].each do |attribute|
    test "does not save a missing #{attribute}" do
      [ nil, "", "   " ].each do |value|
        @reaction[attribute] = value

        assert_not @reaction.save, "Expected #{attribute}=#{value.inspect} to be rejected"
        assert @reaction.errors.of_kind?(attribute, :not_a_number)
      end
    end

    test "does not save a negative #{attribute}" do
      [ -1, "-1" ].each do |value|
        @reaction[attribute] = value

        assert_not @reaction.save, "Expected #{attribute}=#{value.inspect} to be rejected"
        assert @reaction.errors.of_kind?(attribute, :greater_than_or_equal_to)
      end
    end

    test "does not save a decimal #{attribute}" do
      [ 1.5, "1.5", 1.0, "1.0" ].each do |value|
        @reaction[attribute] = value

        assert_not @reaction.save, "Expected #{attribute}=#{value.inspect} to be rejected"
        assert @reaction.errors.of_kind?(attribute, :not_an_integer)
      end
    end

    test "does not save a nonnumeric #{attribute}" do
      [ "abc", "1abc", true, false ].each do |value|
        @reaction[attribute] = value

        assert_not @reaction.save, "Expected #{attribute}=#{value.inspect} to be rejected"
        assert @reaction.errors.of_kind?(attribute, :not_a_number)
      end
    end

    test "allows zero and positive integers for #{attribute}" do
      [ 0, "0", 1, "12" ].each do |value|
        @reaction[attribute] = value

        assert @reaction.save, "Expected #{attribute}=#{value.inspect} to be accepted"
        assert_equal value.to_i, @reaction.reload[attribute]
      end
    end

    test "database rejects a null #{attribute} without validation" do
      @reaction[attribute] = nil

      assert_raises ActiveRecord::NotNullViolation do
        Reaction.transaction(requires_new: true) do
          @reaction.save!(validate: false)
        end
      end
    end

    test "database rejects a negative #{attribute} without validation" do
      @reaction[attribute] = -1

      error = assert_raises ActiveRecord::StatementInvalid do
        Reaction.transaction(requires_new: true) do
          @reaction.save!(validate: false)
        end
      end

      assert_instance_of PG::CheckViolation, error.cause
      assert_equal "reactions_#{attribute}_non_negative",
        error.cause.result.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)
    end
  end

  test "does not save when all three counts are zero" do
    @reaction.assign_attributes(positive_count: 0, neutral_count: 0, negative_count: 0)

    assert_not @reaction.save
    assert_includes @reaction.errors[:base], "リアクション人数を1人以上入力してください"
  end

  test "allows one positive count and two zero counts" do
    [ :positive_count, :neutral_count, :negative_count ].each do |attribute|
      @reaction.assign_attributes(positive_count: 0, neutral_count: 0, negative_count: 0)
      @reaction[attribute] = 1

      assert @reaction.save
      assert_equal 1, @reaction.reload[attribute]
    end
  end

  test "does not save duplicate classroom and feedback target combinations" do
    @reaction.save!
    duplicate = @reaction.dup

    assert_not duplicate.save
    assert duplicate.errors.of_kind?(:classroom_id, :taken)
  end

  test "allows different classrooms for the same feedback target" do
    @reaction.save!
    other_classroom = Classroom.create!(kindergarten: @classroom.kindergarten, name: "すみれ組")
    reaction = @reaction.dup
    reaction.classroom = other_classroom

    assert reaction.save
  end

  test "allows different feedback targets for the same classroom" do
    @reaction.save!
    other_target = FeedbackTarget.create!(dish: @feedback_target.dish, target_date: @feedback_target.target_date + 1.day)
    reaction = @reaction.dup
    reaction.feedback_target = other_target

    assert reaction.save
  end

  test "allows updating an existing record without changing its classroom and feedback target" do
    @reaction.save!

    assert @reaction.update(positive_count: 12)
    assert_equal 12, @reaction.reload.positive_count
    assert_equal @classroom.id, @reaction.classroom_id
    assert_equal @feedback_target.id, @reaction.feedback_target_id
  end

  test "database rejects a null classroom without validation" do
    @reaction.classroom = nil

    assert_raises ActiveRecord::NotNullViolation do
      Reaction.transaction(requires_new: true) do
        @reaction.save!(validate: false)
      end
    end
  end

  test "database rejects a nonexistent classroom without validation" do
    @reaction.classroom_id = Classroom.maximum(:id) + 1

    assert_raises ActiveRecord::InvalidForeignKey do
      Reaction.transaction(requires_new: true) do
        @reaction.save!(validate: false)
      end
    end
  end

  test "database rejects a null feedback target without validation" do
    @reaction.feedback_target = nil

    assert_raises ActiveRecord::NotNullViolation do
      Reaction.transaction(requires_new: true) do
        @reaction.save!(validate: false)
      end
    end
  end

  test "database rejects a nonexistent feedback target without validation" do
    @reaction.feedback_target_id = FeedbackTarget.maximum(:id) + 1

    assert_raises ActiveRecord::InvalidForeignKey do
      Reaction.transaction(requires_new: true) do
        @reaction.save!(validate: false)
      end
    end
  end

  [ :created_at, :updated_at ].each do |attribute|
    test "database rejects a null #{attribute} without validation" do
      @reaction.save!

      assert_raises ActiveRecord::NotNullViolation do
        Reaction.transaction(requires_new: true) do
          @reaction.update_columns(attribute => nil)
        end
      end
    end
  end

  test "database rejects duplicate classroom and feedback target combinations without validation" do
    @reaction.save!

    assert_raises ActiveRecord::RecordNotUnique do
      Reaction.transaction(requires_new: true) do
        @reaction.dup.save!(validate: false)
      end
    end
  end

  test "database rejects all three counts being zero without validation" do
    @reaction.assign_attributes(positive_count: 0, neutral_count: 0, negative_count: 0)

    error = assert_raises ActiveRecord::StatementInvalid do
      Reaction.transaction(requires_new: true) do
        @reaction.save!(validate: false)
      end
    end

    assert_instance_of PG::CheckViolation, error.cause
    assert_equal "reactions_total_count_positive",
      error.cause.result.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)
  end
end
