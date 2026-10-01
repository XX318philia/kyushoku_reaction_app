require "test_helper"

class ClassroomTest < ActiveSupport::TestCase
  setup do
    @kindergarten = Kindergarten.create!(name: "さくら幼稚園")
  end

  test "saves a classroom belonging to a kindergarten with a name and timestamps" do
    classroom = Classroom.new(kindergarten: @kindergarten, name: "ひまわり組")

    assert classroom.save
    classroom.reload
    assert_equal @kindergarten, classroom.kindergarten
    assert_equal "ひまわり組", classroom.name
    assert_not_nil classroom.created_at
    assert_not_nil classroom.updated_at
  end

  test "does not save a classroom without a kindergarten" do
    classroom = Classroom.new(name: "ひまわり組")

    assert_not classroom.save
    assert classroom.errors.of_kind?(:kindergarten, :blank)
  end

  test "does not save a classroom with a nil name" do
    classroom = Classroom.new(kindergarten: @kindergarten, name: nil)

    assert_not classroom.save
    assert classroom.errors.of_kind?(:name, :blank)
  end

  test "does not save a classroom with an empty name" do
    classroom = Classroom.new(kindergarten: @kindergarten, name: "")

    assert_not classroom.save
    assert classroom.errors.of_kind?(:name, :blank)
  end

  test "does not save a classroom with a whitespace-only name" do
    [ "   ", "\t\n", "　" ].each do |name|
      classroom = Classroom.new(kindergarten: @kindergarten, name: name)

      assert_not classroom.save, "Expected #{name.inspect} to be rejected"
      assert classroom.errors.of_kind?(:name, :blank)
    end
  end

  test "does not save duplicate classroom names within the same kindergarten" do
    Classroom.create!(kindergarten: @kindergarten, name: "ひまわり組")
    classroom = Classroom.new(kindergarten: @kindergarten, name: "ひまわり組")

    assert_not classroom.save
    assert classroom.errors.of_kind?(:name, :taken)
  end

  test "allows the same classroom name in different kindergartens" do
    Classroom.create!(kindergarten: @kindergarten, name: "ひまわり組")
    other_kindergarten = Kindergarten.create!(name: "すみれ幼稚園")
    classroom = Classroom.new(kindergarten: other_kindergarten, name: "ひまわり組")

    assert classroom.save
  end

  test "database rejects a null kindergarten even without validation" do
    assert_raises ActiveRecord::NotNullViolation do
      Classroom.transaction(requires_new: true) do
        Classroom.new(name: "ひまわり組").save!(validate: false)
      end
    end
  end

  test "database rejects a nonexistent kindergarten even without validation" do
    missing_kindergarten_id = Kindergarten.maximum(:id) + 1

    assert_raises ActiveRecord::InvalidForeignKey do
      Classroom.transaction(requires_new: true) do
        Classroom.new(kindergarten_id: missing_kindergarten_id, name: "ひまわり組").save!(validate: false)
      end
    end
  end

  test "database rejects a null name even without validation" do
    assert_raises ActiveRecord::NotNullViolation do
      Classroom.transaction(requires_new: true) do
        Classroom.new(kindergarten: @kindergarten, name: nil).save!(validate: false)
      end
    end
  end

  test "database rejects duplicate classroom names within the same kindergarten even without validation" do
    Classroom.create!(kindergarten: @kindergarten, name: "ひまわり組")

    assert_raises ActiveRecord::RecordNotUnique do
      Classroom.transaction(requires_new: true) do
        Classroom.new(kindergarten: @kindergarten, name: "ひまわり組").save!(validate: false)
      end
    end
  end
end
