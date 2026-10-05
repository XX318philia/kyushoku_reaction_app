require "test_helper"

class DishesControllerTest < ActionDispatch::IntegrationTest
  setup do
    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "center-password" }
  end

  test "displays a blank dish registration form with all enum categories" do
    get new_dish_url

    assert_response :success
    assert_select "title", text: "料理マスタ登録 | 給食リアクション"
    assert_select "h2", text: "登録フォーム"
    assert_select "form[action=?][method=post]", dishes_path do
      assert_select "label[for=dish_category]", text: "料理分類"
      assert_select "select[name=?]", "dish[category]" do
        assert_select "option[value='']", text: "料理分類を選択してください", count: 1
        assert_select "option[selected]", count: 0
        assert_select "option", count: 5
        Dish.categories.keys.zip([ "主菜", "副菜", "汁物", "フルーツ・デザート" ]).each do |category, label|
          assert_select "option[value=?]", category, text: label, count: 1
        end
      end
      assert_select "label[for=dish_name]", text: "料理名"
      assert_select "input[type=text][name=?]", "dish[name]"
      assert_select "input[type=text][value]", count: 0
      assert_select "input[type=submit][value=登録]", count: 1
    end
    assert_select "[role=alert]", count: 0
  end

  test "creates a dish and redirects to a fresh registration form" do
    assert_difference "Dish.count", 1 do
      post dishes_url, params: { dish: { name: "野菜スープ", category: "soup" } }
    end

    assert_response :see_other
    assert_redirected_to new_dish_url
    assert_equal "soup", Dish.find_by!(name: "野菜スープ").category

    follow_redirect!

    assert_response :success
    assert_select "input[name=?][value]", "dish[name]", count: 0
    assert_select "select[name=?] option[selected]", "dish[category]", count: 0
    assert_select "[role=alert]", count: 0
  end

  test "creates dishes in each enum category" do
    Dish.categories.each_key do |category|
      assert_difference "Dish.count", 1 do
        post dishes_url, params: { dish: { name: "野菜スープ", category: category } }
      end

      assert_redirected_to new_dish_url
      assert Dish.exists?(name: "野菜スープ", category: category)
    end
  end

  test "uses the model to remove spaces and accept middle dots" do
    assert_difference "Dish.count", 1 do
      post dishes_url, params: { dish: { name: "　フルーツ ・ ヨーグルト ", category: "fruit_or_dessert" } }
    end

    assert_redirected_to new_dish_url
    assert Dish.exists?(name: "フルーツ・ヨーグルト", category: :fruit_or_dessert)
  end

  test "does not register a missing name and retains the category" do
    [ nil, "", " 　" ].each do |name|
      assert_registration_failure(name: name, category: "soup")

      assert_select "select[name=?] option[value=soup][selected]", "dish[category]", count: 1
    end
  end

  test "does not register a missing category and retains the name" do
    [ nil, "" ].each do |category|
      assert_registration_failure(name: "野菜スープ", category: category)

      assert_select "input[name=?][value=?]", "dish[name]", "野菜スープ"
      assert_select "select[name=?] option[value='']", "dish[category]", text: "料理分類を選択してください"
    end
  end

  test "does not register empty required fields" do
    assert_registration_failure(name: "", category: "")
  end

  test "rejects duplicate names and categories and retains both inputs" do
    Dish.create!(name: "野菜スープ", category: :soup)

    assert_registration_failure(name: "野菜スープ", category: "soup")

    assert_select "input[name=?][value=?]", "dish[name]", "野菜スープ"
    assert_select "select[name=?] option[value=soup][selected]", "dish[category]", count: 1
  end

  test "rejects duplicates after the model removes spaces" do
    Dish.create!(name: "野菜スープ", category: :soup)

    assert_registration_failure(name: " 野　菜 スープ　", category: "soup")

    assert_select "input[name=?][value=?]", "dish[name]", "野菜スープ"
  end

  test "allows the same name in a different category" do
    Dish.create!(name: "野菜スープ", category: :soup)

    assert_difference "Dish.count", 1 do
      post dishes_url, params: { dish: { name: "野菜スープ", category: "side_dish" } }
    end

    assert_redirected_to new_dish_url
    assert Dish.exists?(name: "野菜スープ", category: :side_dish)
  end

  test "renders the model errors for invalid names and retains the inputs" do
    assert_registration_failure(name: "カレー1", category: "main_dish")

    assert_select "input[name=?][value=?]", "dish[name]", "カレー1"
    assert_select "select[name=?] option[value=main_dish][selected]", "dish[category]", count: 1
  end

  test "renders the model errors for unknown categories" do
    assert_registration_failure(name: "野菜スープ", category: "unknown")

    assert_select "input[name=?][value=?]", "dish[name]", "野菜スープ"
  end

  test "accepts only the name and category parameters" do
    timestamp = Time.utc(2000, 1, 1)

    assert_difference "Dish.count", 1 do
      post dishes_url, params: { dish: { id: -1, name: "野菜スープ", category: "soup",
        created_at: timestamp, updated_at: timestamp } }
    end

    assert_redirected_to new_dish_url
    dish = Dish.find_by!(name: "野菜スープ", category: :soup)
    assert_not_equal(-1, dish.id)
    assert_not_equal timestamp, dish.created_at
    assert_not_equal timestamp, dish.updated_at
  end

  private

  def assert_registration_failure(attributes)
    dish = Dish.new(attributes)
    assert_not dish.valid?

    assert_no_difference "Dish.count" do
      post dishes_url, params: { dish: attributes }
    end

    assert_response :unprocessable_content
    assert_select "h2", text: "登録フォーム"
    assert_select "form[action=?]", dishes_path
    assert_select "[role=alert] li", count: dish.errors.full_messages.size
    dish.errors.full_messages.each do |message|
      assert_select "[role=alert] li", text: message, count: 1
    end
  end
end
