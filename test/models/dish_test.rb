require "test_helper"

class DishTest < ActiveSupport::TestCase
  setup do
    @dish = Dish.new(name: "野菜スープ", category: :soup)
  end

  test "saves a dish with a name category and timestamps" do
    assert @dish.save
    @dish.reload

    assert_equal "野菜スープ", @dish.name
    assert_equal "soup", @dish.category
    assert_not_nil @dish.created_at
    assert_not_nil @dish.updated_at
  end

  test "retrieves only feedback targets belonging to the dish" do
    @dish.save!
    first_target = FeedbackTarget.create!(dish: @dish, target_date: Date.new(2026, 10, 7))
    second_target = FeedbackTarget.create!(dish: @dish, target_date: Date.new(2026, 10, 8))
    other_dish = Dish.create!(name: "味噌汁", category: :soup)
    FeedbackTarget.create!(dish: other_dish, target_date: Date.new(2026, 10, 9))

    assert_equal [ first_target, second_target ], @dish.reload.feedback_targets.order(:target_date).to_a
  end

  test "does not save a blank name" do
    [ nil, "", "   ", "　", " 　" ].each do |name|
      @dish.name = name

      assert_not @dish.save, "Expected #{name.inspect} to be rejected"
      assert @dish.errors.of_kind?(:name, :blank)
    end
  end

  test "does not save a missing category" do
    [ nil, "", "   " ].each do |category|
      @dish.category = category

      assert_not @dish.save
      assert @dish.errors.of_kind?(:category, :blank)
    end
  end

  test "stores and retrieves all four categories as integers" do
    categories = { "main_dish" => 0, "side_dish" => 1, "soup" => 2, "fruit_or_dessert" => 3 }

    assert_equal categories, Dish.categories

    categories.each do |category, value|
      dish = Dish.create!(name: "野菜スープ", category: category.to_sym)
      dish.reload

      assert_equal category, dish.category
      assert_equal value, dish.category_before_type_cast
    end
  end

  test "accepts category integer values" do
    [ "main_dish", "side_dish", "soup", "fruit_or_dessert" ].each_with_index do |category, value|
      @dish.category = value

      assert @dish.save
      assert_equal category, @dish.reload.category
    end
  end

  test "rejects unknown categories with validation errors" do
    [ :unknown, "unknown", -1, 4, "4" ].each do |category|
      @dish.category = category

      assert_not @dish.save, "Expected #{category.inspect} to be rejected"
      assert @dish.errors.of_kind?(:category, :inclusion)
    end
  end

  test "does not save the same name and category twice" do
    @dish.save!
    dish = Dish.new(name: "野菜スープ", category: :soup)

    assert_not dish.save
    assert dish.errors.of_kind?(:name, :taken)
  end

  test "allows the same name in different categories" do
    @dish.save!
    dish = Dish.new(name: "野菜スープ", category: :side_dish)

    assert dish.save
  end

  test "allows different names in the same category" do
    @dish.save!
    dish = Dish.new(name: "味噌汁", category: :soup)

    assert dish.save
  end

  test "removes half-width and full-width spaces before validation and storage" do
    [ " 野菜スープ ", "　野菜スープ　", "野 菜ス ープ", "野　菜ス　ープ", " 　野 菜　ス ー　プ　 " ].each do |name|
      @dish.name = name

      assert @dish.valid?, "Expected #{name.inspect} to be accepted after removing spaces"
      assert_equal "野菜スープ", @dish.name
      assert @dish.save
      assert_equal "野菜スープ", @dish.reload.name
    end
  end

  test "rejects duplicates after removing spaces" do
    @dish.name = " 野　菜 スープ　"
    @dish.save!
    dish = Dish.new(name: "　野 菜ス　ープ ", category: :soup)

    assert_not dish.save
    assert_equal "野菜スープ", dish.name
    assert dish.errors.of_kind?(:name, :taken)
  end

  test "allows a normalized name in a different category" do
    @dish.save!
    dish = Dish.new(name: "　野 菜ス　ープ ", category: :side_dish)

    assert dish.save
    assert_equal "野菜スープ", dish.reload.name
  end

  test "accepts hiragana katakana kanji long vowel marks and middle dots" do
    [ "とりのからあげ", "ポテトサラダ", "野菜炒め", "カレー", "フルーツ・ヨーグルト", "鶏のクリーム煮" ].each do |name|
      dish = Dish.new(name: name, category: :main_dish)

      assert dish.save, "Expected #{name.inspect} to be accepted"
      assert_equal name, dish.reload.name
    end
  end

  test "accepts half-width katakana extended kana and kanji letters" do
    [ "ｶﾚー", "ㇰ", "髙菜炒め", "𠮷野汁" ].each do |name|
      dish = Dish.new(name: name, category: :main_dish)

      assert dish.save, "Expected #{name.inspect} to be accepted"
      assert_equal name, dish.reload.name
    end
  end

  test "rejects hiragana katakana and kanji iteration marks" do
    [ "ゝ", "ゞ", "ヽ", "ヾ", "々", "〻" ].each do |mark|
      @dish.name = "野菜#{mark}スープ"

      assert_not @dish.save, "Expected #{mark.inspect} to be rejected"
      assert @dish.errors.of_kind?(:name, :invalid)
    end
  end

  test "rejects Han radicals and numerals" do
    [ "⼀", "⺀", "〇", "〡" ].each do |character|
      @dish.name = "野菜#{character}スープ"

      assert_not @dish.save, "Expected #{character.inspect} to be rejected"
      assert @dish.errors.of_kind?(:name, :invalid)
    end
  end

  test "rejects letters digits parentheses and other symbols" do
    [ "カレーA", "カレーａ", "カレー1", "カレー１", "カレー(辛口)", "カレー（辛口）",
      "カレー-ライス", "カレー／ライス", "カレー、ライス", "カレー🙂" ].each do |name|
      @dish.name = name

      assert_not @dish.save, "Expected #{name.inspect} to be rejected"
      assert @dish.errors.of_kind?(:name, :invalid)
    end
  end

  test "rejects tabs newlines and whitespace other than half-width or full-width spaces" do
    [ "野菜\tスープ", "野菜\nスープ", "野菜スープ\n", "野菜\u00a0スープ" ].each do |name|
      @dish.name = name

      assert_not @dish.save, "Expected #{name.inspect} to be rejected"
      assert @dish.errors.of_kind?(:name, :invalid)
    end
  end

  test "preserves distinct hiragana katakana and kanji spellings" do
    assert_difference "Dish.count", 3 do
      [ "からあげ", "カラアゲ", "唐揚げ" ].each do |name|
        dish = Dish.create!(name: name, category: :main_dish)

        assert_equal name, dish.reload.name
      end
    end
  end

  test "database rejects a null name without validation" do
    assert_raises ActiveRecord::NotNullViolation do
      Dish.transaction(requires_new: true) do
        Dish.new(name: nil, category: :soup).save!(validate: false)
      end
    end
  end

  test "database rejects a null category without validation" do
    assert_raises ActiveRecord::NotNullViolation do
      Dish.transaction(requires_new: true) do
        Dish.new(name: "野菜スープ", category: nil).save!(validate: false)
      end
    end
  end

  test "database rejects duplicate names and categories without validation" do
    @dish.save!

    assert_raises ActiveRecord::RecordNotUnique do
      Dish.transaction(requires_new: true) do
        Dish.new(name: "野菜スープ", category: :soup).save!(validate: false)
      end
    end
  end
end
