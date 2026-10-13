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

  test "destroy removes dependent reactions while retaining other targets and master records" do
    @feedback_target.save!
    classroom = create_summary_classroom
    other_classroom = classroom.kindergarten.classrooms.create!(name: "すみれ組")
    [ classroom, other_classroom ].each do |item|
      Reaction.create!(classroom: item, feedback_target: @feedback_target,
        positive_count: 1, neutral_count: 0, negative_count: 0)
    end
    other_target = FeedbackTarget.create!(dish: @dish, target_date: @feedback_target.target_date - 1.day)
    other_reaction = Reaction.create!(classroom: classroom, feedback_target: other_target,
      positive_count: 0, neutral_count: 1, negative_count: 0)
    retained_data = [ Dish, Kindergarten, Classroom ].map { |model| model.order(:id).map(&:attributes) }

    assert_difference "FeedbackTarget.count", -1 do
      assert_difference "Reaction.count", -2 do
        assert @feedback_target.destroy
      end
    end

    assert @feedback_target.destroyed?
    assert_equal other_target, FeedbackTarget.find(other_target.id)
    assert_equal other_reaction, Reaction.find(other_reaction.id)
    assert_equal retained_data, [ Dish, Kindergarten, Classroom ].map { |model| model.order(:id).map(&:attributes) }
  end

  test "destroy succeeds without reactions" do
    @feedback_target.save!

    assert_difference "FeedbackTarget.count", -1 do
      assert_no_difference "Reaction.count" do
        assert @feedback_target.destroy
      end
    end
    assert Dish.exists?(@dish.id)
  end

  test "a dependent destroy abort rolls back already destroyed reactions" do
    @feedback_target.save!
    classroom = create_summary_classroom
    other_classroom = classroom.kindergarten.classrooms.create!(name: "すみれ組")
    reactions = [ classroom, other_classroom ].map do |item|
      Reaction.create!(classroom: item, feedback_target: @feedback_target,
        positive_count: 1, neutral_count: 0, negative_count: 0)
    end
    original_data = reactions.map(&:attributes)
    callback = -> { throw :abort if id == reactions.last.id }
    Reaction.set_callback(:destroy, :before, callback)
    begin
      assert_no_difference [ "FeedbackTarget.count", "Reaction.count" ] do
        assert_not @feedback_target.destroy
      end
    ensure
      Reaction.skip_callback(:destroy, :before, callback)
    end

    assert_equal original_data, Reaction.where(feedback_target: @feedback_target).order(:id).map(&:attributes)
    assert FeedbackTarget.exists?(@feedback_target.id)
  end

  test "summarizes counts and percentages across kindergartens and classrooms" do
    @feedback_target.save!
    kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    other_kindergarten = Kindergarten.create!(name: "ひまわり幼稚園")
    first_classroom = Classroom.create!(kindergarten: kindergarten, name: "ひまわり組")
    second_classroom = Classroom.create!(kindergarten: kindergarten, name: "すみれ組")
    third_classroom = Classroom.create!(kindergarten: other_kindergarten, name: "ひまわり組")
    FactoryBot.create(:reaction, classroom: first_classroom, feedback_target: @feedback_target,
      positive_count: 10, neutral_count: 0, negative_count: 0)
    FactoryBot.create(:reaction, classroom: second_classroom, feedback_target: @feedback_target,
      positive_count: 0, neutral_count: 20, negative_count: 0)
    FactoryBot.create(:reaction, classroom: third_classroom, feedback_target: @feedback_target,
      positive_count: 5, neutral_count: 5, negative_count: 10)

    assert_equal({
      positive_count: 15, neutral_count: 25, negative_count: 10, total_count: 50,
      positive_percentage: 30.0, neutral_percentage: 50.0, negative_percentage: 20.0
    }, @feedback_target.reaction_summary)
  end

  test "summarizes only reactions for its target date and dish" do
    @feedback_target.save!
    next_day_target = FeedbackTarget.create!(dish: @dish, target_date: @feedback_target.target_date + 1.day)
    other_dish = Dish.create!(name: "味噌汁", category: :soup)
    other_dish_target = FeedbackTarget.create!(dish: other_dish, target_date: @feedback_target.target_date + 2.days)
    classroom = create_summary_classroom
    Reaction.create!(classroom: classroom, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 1)
    Reaction.create!(classroom: classroom, feedback_target: next_day_target,
      positive_count: 100, neutral_count: 200, negative_count: 300)
    Reaction.create!(classroom: classroom, feedback_target: other_dish_target,
      positive_count: 300, neutral_count: 200, negative_count: 100)

    assert_equal({
      positive_count: 2, neutral_count: 1, negative_count: 1, total_count: 4,
      positive_percentage: 50.0, neutral_percentage: 25.0, negative_percentage: 25.0
    }, @feedback_target.reaction_summary)
  end

  test "returns zero counts and nil percentages without reactions" do
    @feedback_target.save!

    assert_equal({
      positive_count: 0, neutral_count: 0, negative_count: 0, total_count: 0,
      positive_percentage: nil, neutral_percentage: nil, negative_percentage: nil
    }, @feedback_target.reaction_summary)
  end

  test "returns zero percent for a zero count when other counts are positive" do
    @feedback_target.save!
    FactoryBot.create(:reaction, feedback_target: @feedback_target,
      positive_count: 0, neutral_count: 1, negative_count: 3)

    assert_equal({
      positive_count: 0, neutral_count: 1, negative_count: 3, total_count: 4,
      positive_percentage: 0.0, neutral_percentage: 25.0, negative_percentage: 75.0
    }, @feedback_target.reaction_summary)
  end

  test "returns one hundred percent when only one reaction type has a positive count" do
    @feedback_target.save!
    reaction = FactoryBot.build(:reaction, feedback_target: @feedback_target)

    [ :positive, :neutral, :negative ].each do |type|
      reaction.assign_attributes(positive_count: 0, neutral_count: 0, negative_count: 0)
      reaction["#{type}_count"] = 6
      reaction.save!
      summary = @feedback_target.reaction_summary

      assert_equal 6, summary[:total_count]
      [ :positive, :neutral, :negative ].each do |item|
        assert_equal(item == type ? 6 : 0, summary[:"#{item}_count"])
        assert_equal(item == type ? 100.0 : 0.0, summary[:"#{item}_percentage"])
      end
    end
  end

  test "returns percentages without rounding for display" do
    @feedback_target.save!
    FactoryBot.create(:reaction, feedback_target: @feedback_target,
      positive_count: 1, neutral_count: 2, negative_count: 3)

    summary = @feedback_target.reaction_summary

    assert_equal 6, summary[:total_count]
    assert_in_delta 100.0 / 6, summary[:positive_percentage], 1e-10
    assert_in_delta 200.0 / 6, summary[:neutral_percentage], 1e-10
    assert_equal 50.0, summary[:negative_percentage]
  end

  test "recalculates after creates and updates without double counting loaded reactions" do
    @feedback_target.save!
    first_classroom = create_summary_classroom
    second_classroom = Classroom.create!(kindergarten: first_classroom.kindergarten, name: "すみれ組")
    @feedback_target.reactions.load
    assert_equal 0, @feedback_target.reaction_summary[:total_count]

    first_reaction = FactoryBot.create(:reaction, classroom: first_classroom, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 1)
    assert_equal 4, @feedback_target.reaction_summary[:total_count]

    FactoryBot.create(:reaction, classroom: second_classroom, feedback_target: @feedback_target,
      positive_count: 3, neutral_count: 2, negative_count: 1)
    assert_equal 10, @feedback_target.reaction_summary[:total_count]

    first_reaction.update!(positive_count: 1, neutral_count: 3, negative_count: 2)
    summary = @feedback_target.reaction_summary

    assert_equal 4, summary[:positive_count]
    assert_equal 5, summary[:neutral_count]
    assert_equal 3, summary[:negative_count]
    assert_equal 12, summary[:total_count]
    assert_in_delta 100.0 / 3, summary[:positive_percentage], 1e-10
    assert_in_delta 500.0 / 12, summary[:neutral_percentage], 1e-10
    assert_equal 25.0, summary[:negative_percentage]
    assert_equal summary, @feedback_target.reaction_summary
    assert_equal 2, @feedback_target.reactions.count
  end

  test "summarizes saved counts rather than unsaved changes and new reactions" do
    @feedback_target.save!
    classroom = create_summary_classroom
    Reaction.create!(classroom: classroom, feedback_target: @feedback_target,
      positive_count: 8, neutral_count: 1, negative_count: 1)
    other_classroom = Classroom.create!(kindergarten: classroom.kindergarten, name: "すみれ組")
    @feedback_target.reactions.load
    @feedback_target.reactions.first.positive_count = 100
    @feedback_target.reactions.build(classroom: other_classroom,
      positive_count: 100, neutral_count: 100, negative_count: 100)

    assert_equal({
      positive_count: 8, neutral_count: 1, negative_count: 1, total_count: 10,
      positive_percentage: 80.0, neutral_percentage: 10.0, negative_percentage: 10.0
    }, @feedback_target.reaction_summary)
  end

  test "does not change saved feedback targets or reactions when summarizing" do
    @feedback_target.save!
    FactoryBot.create(:reaction, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 1)
    saved_targets = FeedbackTarget.order(:id).map(&:attributes)
    saved_reactions = Reaction.order(:id).map(&:attributes)

    2.times { @feedback_target.reaction_summary }

    assert_equal saved_targets, FeedbackTarget.order(:id).map(&:attributes)
    assert_equal saved_reactions, Reaction.order(:id).map(&:attributes)
  end

  test "fetches all three count sums in one aggregate query" do
    @feedback_target.save!
    FactoryBot.create(:reaction, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 1)
    queries = []
    subscriber = ->(event) do
      queries << event.payload[:sql] unless [ "SCHEMA", "TRANSACTION" ].include?(event.payload[:name])
    end

    Reaction.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        @feedback_target.reaction_summary
      end
    end

    assert_equal 1, queries.size
    assert_equal 3, queries.first.scan(/\bSUM\s*\(/i).size
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

  private

  def create_summary_classroom
    kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    Classroom.create!(kindergarten: kindergarten, name: "ひまわり組")
  end
end
