require "test_helper"

class KindergartenTest < ActiveSupport::TestCase
  test "returns only classrooms belonging to the kindergarten" do
    kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    other_kindergarten = Kindergarten.create!(name: "すみれ幼稚園")
    sunflower_classroom = Classroom.create!(kindergarten: kindergarten, name: "ひまわり組")
    tulip_classroom = Classroom.create!(kindergarten: kindergarten, name: "ちゅーりっぷ組")
    Classroom.create!(kindergarten: other_kindergarten, name: "ひまわり組")

    assert_equal [ sunflower_classroom, tulip_classroom ], kindergarten.reload.classrooms.order(:id).to_a
  end

  test "saves a kindergarten with a name and timestamps" do
    kindergarten = Kindergarten.new(name: "さくら幼稚園")

    assert kindergarten.save
    kindergarten.reload
    assert_equal "さくら幼稚園", kindergarten.name
    assert_not_nil kindergarten.created_at
    assert_not_nil kindergarten.updated_at
  end

  test "does not save a kindergarten with a nil name" do
    kindergarten = Kindergarten.new(name: nil)

    assert_not kindergarten.save
    assert kindergarten.errors.of_kind?(:name, :blank)
  end

  test "does not save a kindergarten with an empty name" do
    kindergarten = Kindergarten.new(name: "")

    assert_not kindergarten.save
    assert kindergarten.errors.of_kind?(:name, :blank)
  end

  test "does not save a kindergarten with a whitespace-only name" do
    [ "   ", "\t\n", "　" ].each do |name|
      kindergarten = Kindergarten.new(name: name)

      assert_not kindergarten.save, "Expected #{name.inspect} to be rejected"
      assert kindergarten.errors.of_kind?(:name, :blank)
    end
  end

  test "allows duplicate kindergarten names" do
    Kindergarten.create!(name: "さくら幼稚園")
    kindergarten = Kindergarten.new(name: "さくら幼稚園")

    assert kindergarten.save
  end

  test "database rejects a null name even without validation" do
    assert_raises ActiveRecord::NotNullViolation do
      Kindergarten.transaction(requires_new: true) do
        Kindergarten.new(name: nil).save!(validate: false)
      end
    end
  end
end
