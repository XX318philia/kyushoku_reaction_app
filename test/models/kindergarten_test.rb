require "test_helper"

class KindergartenTest < ActiveSupport::TestCase
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
