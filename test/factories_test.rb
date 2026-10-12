require "test_helper"

class FactoriesTest < ActiveSupport::TestCase
  test "builds valid unsaved records for all six models without saving associations" do
    models = [ User, Kindergarten, Classroom, Dish, FeedbackTarget, Reaction ]

    assert_no_difference models.map { |model| "#{model.name}.count" } do
      %i[ user kindergarten classroom dish feedback_target reaction ].each do |factory|
        record = FactoryBot.build(factory)

        assert record.valid?, "#{factory}: #{record.errors.full_messages.join(", ")}"
        assert record.new_record?
      end
    end
  end

  test "repeatedly creates and saves valid records for all six models" do
    %i[ user kindergarten classroom dish feedback_target reaction ].each do |factory|
      records = FactoryBot.create_list(factory, 3)

      records.each do |record|
        assert record.persisted?
        assert record.reload.valid?, "#{factory}: #{record.errors.full_messages.join(", ")}"
      end
    end
  end

  test "builds and creates kindergarten users with a kindergarten and usable password" do
    [ FactoryBot.build(:user), FactoryBot.create(:user).reload ].each do |user|
      assert user.kindergarten?
      assert_instance_of Kindergarten, user.kindergarten
      assert user.kindergarten.valid?
      assert_equal user.persisted?, user.kindergarten.persisted?
      if user.persisted?
        assert_equal user.kindergarten.id, user.kindergarten_id
      else
        assert_nil user.kindergarten_id
      end
      assert_equal user, user.authenticate("password")
    end
  end

  test "builds and creates center users without creating a kindergarten" do
    assert_no_difference "Kindergarten.count" do
      [ FactoryBot.build(:user, :center), FactoryBot.create(:user, :center).reload ].each do |user|
        assert user.valid?
        assert user.center?
        assert_nil user.kindergarten
        assert_nil user.kindergarten_id
        assert_equal user, user.authenticate("password")
      end
    end
  end

  test "generates unique login ids across both roles and distinct kindergarten associations" do
    kindergarten_users = FactoryBot.create_list(:user, 3)
    center_users = FactoryBot.create_list(:user, 3, :center)
    login_ids = (kindergarten_users + center_users).map(&:login_id)
    kindergarten_ids = kindergarten_users.map(&:kindergarten_id)

    assert_equal 6, login_ids.uniq.size
    assert_equal 3, kindergarten_ids.uniq.size
  end

  test "creates classrooms with distinct names within the same kindergarten" do
    kindergarten = FactoryBot.create(:kindergarten)
    classrooms = FactoryBot.create_list(:classroom, 3, kindergarten: kindergarten)

    assert_equal 3, classrooms.map(&:name).uniq.size
    assert_equal classrooms.map(&:id).sort, kindergarten.reload.classrooms.pluck(:id).sort
    classrooms.each { |classroom| assert_equal kindergarten, classroom.kindergarten }
  end

  test "creates dishes with valid distinct names in the same category across multi-digit sequences" do
    dishes = FactoryBot.create_list(:dish, 12)

    assert_equal 12, dishes.map(&:name).uniq.size
    assert_equal 1, dishes.map(&:category).uniq.size
    dishes.each do |dish|
      assert dish.reload.valid?, dish.errors.full_messages.join(", ")
      assert Dish.categories.key?(dish.category)
    end
  end

  test "creates feedback targets with unique dates for the same dish" do
    dish = FactoryBot.create(:dish)
    targets = FactoryBot.create_list(:feedback_target, 3, dish: dish)

    assert_equal 3, targets.map(&:target_date).uniq.size
    assert_equal targets.map(&:id).sort, dish.reload.feedback_targets.pluck(:id).sort
    targets.each { |target| assert_equal dish, target.dish }
  end

  test "builds and creates reactions with valid counts and associated records" do
    [ FactoryBot.build(:reaction), FactoryBot.create(:reaction).reload ].each do |reaction|
      associations = [ reaction.classroom, reaction.classroom.kindergarten,
        reaction.feedback_target, reaction.feedback_target.dish ]

      associations.each do |record|
        assert record.valid?
        assert_equal reaction.persisted?, record.persisted?
      end
      if reaction.persisted?
        assert_equal reaction.classroom.id, reaction.classroom_id
        assert_equal reaction.feedback_target.id, reaction.feedback_target_id
      else
        assert_nil reaction.classroom_id
        assert_nil reaction.feedback_target_id
      end

      counts = [ reaction.positive_count, reaction.neutral_count, reaction.negative_count ]
      counts.each do |count|
        assert_kind_of Integer, count
        assert_operator count, :>=, 0
      end
      assert_operator counts.sum, :>, 0
    end
  end

  test "creates reactions from multiple classrooms for the same feedback target" do
    kindergarten = FactoryBot.create(:kindergarten)
    classrooms = FactoryBot.create_list(:classroom, 3, kindergarten: kindergarten)
    target = FactoryBot.create(:feedback_target)
    reactions = classrooms.map do |classroom|
      FactoryBot.create(:reaction, classroom: classroom, feedback_target: target)
    end

    assert_equal reactions.map(&:id).sort, target.reload.reactions.pluck(:id).sort
    reactions.zip(classrooms).each do |reaction, classroom|
      assert_equal classroom, reaction.reload.classroom
      assert_equal target, reaction.feedback_target
      assert_equal [ reaction.id ], classroom.reload.reactions.pluck(:id)
    end
  end

  test "creates reactions for the same classroom with distinct feedback targets" do
    classroom = FactoryBot.create(:classroom)
    reactions = FactoryBot.create_list(:reaction, 3, classroom: classroom)

    assert_equal 3, reactions.map(&:feedback_target_id).uniq.size
    assert_equal reactions.map(&:id).sort, classroom.reload.reactions.pluck(:id).sort
    reactions.each { |reaction| assert_equal classroom, reaction.classroom }
  end
end
