require "test_helper"

class DishesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(login_id: "Center", password: "center-password", role: :center)
    post center_login_path, params: { login_id: @user.login_id, password: "center-password" }
  end

  test "redirects logged out users to center login without an alert or writes" do
    delete center_logout_path

    assert_login_required
  end

  test "redirects a deleted session user to center login without an alert or writes" do
    @user.destroy!

    assert_login_required
  end

  test "redirects kindergarten users to entry with an alert without creating or updating dishes" do
    user = User.create!(login_id: "Sakura", password: "kindergarten-password",
      role: :kindergarten, kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
    post kindergarten_login_path, params: { login_id: user.login_id, password: "kindergarten-password" }
    dish = Dish.create!(name: "カレー", category: :main_dish)
    original_attributes = dish.attributes

    get new_dish_url
    assert_access_denied

    assert_no_difference "Dish.count" do
      post dishes_url, params: { dish: { id: dish.id, name: "野菜スープ", category: "soup" } }
    end
    assert_access_denied
    assert_equal original_attributes, dish.reload.attributes
    assert_equal user.id, request.session[:user_id]
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

  test "creates a dish and redirects to the feedback target setting form" do
    assert_difference "Dish.count", 1 do
      post dishes_url, params: { dish: { name: "野菜スープ", category: "soup" } }
    end

    assert_response :see_other
    assert_redirected_to new_feedback_target_url
    assert_equal "soup", Dish.find_by!(name: "野菜スープ").category

    follow_redirect!

    assert_response :success
    assert_select "h2", text: "設定フォーム"
    assert_select "form[action=?]", feedback_targets_path
    assert_select "select[name=?] option", "feedback_target[dish_id]", text: "野菜スープ（汁物）", count: 1
    assert_select "select[name=?] option[selected]", "feedback_target[dish_id]", count: 0
    assert_select "[role=alert]", count: 0
  end

  test "creates dishes in each enum category" do
    Dish.categories.each_key do |category|
      assert_difference "Dish.count", 1 do
        post dishes_url, params: { dish: { name: "野菜スープ", category: category } }
      end

      assert_redirected_to new_feedback_target_url
      assert Dish.exists?(name: "野菜スープ", category: category)
    end
  end

  test "uses the model to remove spaces and accept middle dots" do
    assert_difference "Dish.count", 1 do
      post dishes_url, params: { dish: { name: "　フルーツ ・ ヨーグルト ", category: "fruit_or_dessert" } }
    end

    assert_redirected_to new_feedback_target_url
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

    assert_redirected_to new_feedback_target_url
    assert Dish.exists?(name: "野菜スープ", category: :side_dish)
  end

  test "renders the model errors for invalid names and retains the inputs" do
    assert_registration_failure(name: "カレー1", category: "main_dish")

    assert_select "input[name=?][value=?]", "dish[name]", "カレー1"
    assert_select "select[name=?] option[value=main_dish][selected]", "dish[category]", count: 1
  end

  test "rejects symbol-only names and leading symbols and retains both inputs" do
    [ "・", "ー", "・ー・", "・カレー", "ーカレー" ].each do |name|
      assert_registration_failure(name: name, category: "main_dish")

      assert_select "input[name=?][value=?]", "dish[name]", name
      assert_select "select[name=?] option[value=main_dish][selected]", "dish[category]", count: 1
    end
  end

  test "rejects leading symbols after removing spaces and retains normalized inputs" do
    { " ・ " => "・", "　ー　" => "ー", " 　・ ー　・　 " => "・ー・",
      " 　・ カ　レー " => "・カレー", "　 ー カ　レー　 " => "ーカレー" }.each do |name, normalized_name|
      assert_registration_failure(name: name, category: "main_dish")

      assert_select "input[name=?][value=?]", "dish[name]", normalized_name
      assert_select "select[name=?] option[value=main_dish][selected]", "dish[category]", count: 1
    end
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

    assert_redirected_to new_feedback_target_url
    dish = Dish.find_by!(name: "野菜スープ", category: :soup)
    assert_not_equal(-1, dish.id)
    assert_not_equal timestamp, dish.created_at
    assert_not_equal timestamp, dish.updated_at
  end

  private

  def assert_login_required
    get new_dish_url
    assert_response :see_other
    assert_redirected_to center_login_url
    assert_nil flash[:alert]

    assert_no_difference "Dish.count" do
      post dishes_url, params: { dish: { name: "野菜スープ", category: "soup" } }
    end
    assert_response :see_other
    assert_redirected_to center_login_url
    assert_nil flash[:alert]
  end

  def assert_access_denied
    assert_response :see_other
    assert_redirected_to new_reaction_url
    assert_equal "このページにはアクセスできません", flash[:alert]
  end

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
