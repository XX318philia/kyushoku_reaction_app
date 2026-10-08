require "test_helper"

class FeedbackTargetTest < ActiveSupport::TestCase
  setup do
    @dish = Dish.create!(name: "野菜スープ", category: :soup)
    @feedback_target = FeedbackTarget.new(dish: @dish, target_date: Date.new(2026, 10, 7))
  end

  test "saves a feedback target with a dish date and timestamps" do
    assert @feedback_target.save
    @feedback_target.reload

    assert_equal @dish.id, @feedback_target.dish_id
    assert_equal @dish, @feedback_target.dish
    assert_equal Date.new(2026, 10, 7), @feedback_target.target_date
    assert_not_nil @feedback_target.created_at
    assert_not_nil @feedback_target.updated_at
  end

  test "does not save without a dish" do
    @feedback_target.dish = nil

    assert_not @feedback_target.save
    assert @feedback_target.errors.of_kind?(:dish, :blank)
  end

  test "retrieves only reactions belonging to the feedback target" do
    @feedback_target.save!
    other_target = FeedbackTarget.create!(dish: @dish, target_date: @feedback_target.target_date + 1.day)
    kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    first_classroom = Classroom.create!(kindergarten: kindergarten, name: "ひまわり組")
    second_classroom = Classroom.create!(kindergarten: kindergarten, name: "すみれ組")
    first_reaction = Reaction.create!(classroom: first_classroom, feedback_target: @feedback_target,
      positive_count: 1, neutral_count: 0, negative_count: 0)
    second_reaction = Reaction.create!(classroom: second_classroom, feedback_target: @feedback_target,
      positive_count: 0, neutral_count: 1, negative_count: 0)
    Reaction.create!(classroom: first_classroom, feedback_target: other_target,
      positive_count: 0, neutral_count: 0, negative_count: 1)

    assert_equal [ first_reaction, second_reaction ], @feedback_target.reload.reactions.order(:classroom_id).to_a
  end

  test "does not save with a nonexistent dish" do
    @feedback_target.dish_id = Dish.maximum(:id) + 1

    assert_not @feedback_target.save
    assert @feedback_target.errors.of_kind?(:dish, :blank)
  end

  test "does not save without a target date" do
    @feedback_target.target_date = nil

    assert_not @feedback_target.save
    assert @feedback_target.errors.of_kind?(:target_date, :blank)
  end

  test "does not save the same dish and date twice" do
    @feedback_target.save!
    feedback_target = FeedbackTarget.new(dish: @dish, target_date: @feedback_target.target_date)

    assert_not feedback_target.save
    assert feedback_target.errors.of_kind?(:target_date, :taken)
  end

  test "allows the same dish on different dates" do
    @feedback_target.save!
    feedback_target = FeedbackTarget.new(dish: @dish, target_date: @feedback_target.target_date + 1.day)

    assert feedback_target.save
    assert_equal @dish, feedback_target.reload.dish
  end

  test "does not save different dishes on the same date" do
    @feedback_target.save!
    other_dish = Dish.create!(name: "味噌汁", category: :soup)
    feedback_target = FeedbackTarget.new(dish: other_dish, target_date: @feedback_target.target_date)

    assert_not feedback_target.save
    assert feedback_target.errors.of_kind?(:target_date, :taken)
  end

  test "allows updating an existing record without changing its date" do
    @feedback_target.save!
    other_dish = Dish.create!(name: "味噌汁", category: :soup)

    assert @feedback_target.update(dish: other_dish)
    assert_equal other_dish, @feedback_target.reload.dish
    assert_equal Date.new(2026, 10, 7), @feedback_target.target_date
  end

  test "database rejects a null dish without validation" do
    @feedback_target.dish = nil

    assert_raises ActiveRecord::NotNullViolation do
      FeedbackTarget.transaction(requires_new: true) do
        @feedback_target.save!(validate: false)
      end
    end
  end

  test "database rejects a nonexistent dish without validation" do
    @feedback_target.dish_id = Dish.maximum(:id) + 1

    assert_raises ActiveRecord::InvalidForeignKey do
      FeedbackTarget.transaction(requires_new: true) do
        @feedback_target.save!(validate: false)
      end
    end
  end

  test "database rejects a null target date without validation" do
    @feedback_target.target_date = nil

    assert_raises ActiveRecord::NotNullViolation do
      FeedbackTarget.transaction(requires_new: true) do
        @feedback_target.save!(validate: false)
      end
    end
  end

  test "database rejects duplicate dates for the same dish without validation" do
    @feedback_target.save!

    assert_raises ActiveRecord::RecordNotUnique do
      FeedbackTarget.transaction(requires_new: true) do
        FeedbackTarget.new(dish: @dish, target_date: @feedback_target.target_date).save!(validate: false)
      end
    end
  end

  test "database rejects duplicate dates for different dishes without validation" do
    @feedback_target.save!
    other_dish = Dish.create!(name: "味噌汁", category: :soup)

    assert_raises ActiveRecord::RecordNotUnique do
      FeedbackTarget.transaction(requires_new: true) do
        FeedbackTarget.new(dish: other_dish, target_date: @feedback_target.target_date).save!(validate: false)
      end
    end
  end
end
