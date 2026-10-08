require "test_helper"

class ReactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 8, 0, 30)
    @kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    @user = User.create!(login_id: "Sakura", password: "kindergarten-password",
      role: :kindergarten, kindergarten: @kindergarten)
    @classrooms = [ "年少", "年中", "年長" ].map { |name| @kindergarten.classrooms.create!(name: name) }
    @dish = Dish.create!(name: "カレー", category: :main_dish)
    @feedback_target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    post kindergarten_login_path, params: { login_id: @user.login_id, password: "kindergarten-password" }
  end

  test "displays today's date and dish with a class selector and no reaction inputs" do
    get new_reaction_url

    assert_response :success
    assert_select "title", text: "リアクション入力 | 給食リアクション"
    assert_select "h2", text: "入力フォーム"
    assert_select "time[datetime='2026-10-08']", text: "2026年10月8日"
    assert_select "main p", text: "対象料理：カレー（主菜）"
    assert_select "label[for=classroom_id]", text: "担当クラス"
    assert_select "select[name=classroom_id]:not([disabled])" do
      assert_select "option[value='']", text: "担当クラス", count: 1
      assert_select "option[selected]", count: 0
      assert_select "option", count: @classrooms.size + 1
      @classrooms.each do |classroom|
        assert_select "option[value=?]", classroom.id, text: classroom.name, count: 1
      end
    end
    assert_select "main form, main input, main button", count: 0
  end

  test "displays Japanese labels for all four dish categories" do
    { main_dish: "主菜", side_dish: "副菜", soup: "汁物", fruit_or_dessert: "フルーツ・デザート" }.each do |category, label|
      @dish.update!(category: category)

      get new_reaction_url

      assert_response :success
      assert_select "main p", text: "対象料理：カレー（#{label}）", count: 1
    end
  end

  test "ignores requested dates and never displays yesterday's or tomorrow's dish" do
    yesterday_dish = Dish.create!(name: "肉じゃが", category: :main_dish)
    tomorrow_dish = Dish.create!(name: "野菜スープ", category: :soup)
    FeedbackTarget.create!(dish: yesterday_dish, target_date: Date.yesterday)
    FeedbackTarget.create!(dish: tomorrow_dish, target_date: Date.tomorrow)

    [ Date.yesterday, Date.tomorrow ].each do |date|
      get new_reaction_url, params: { target_date: date, reaction: { target_date: date } }

      assert_response :success
      assert_select "time[datetime=?]", Date.current.iso8601
      assert_select "main p", text: "対象料理：カレー（主菜）", count: 1
      assert_select "main", text: /肉じゃが|野菜スープ/, count: 0
      assert_select "main [name*=target_date], main input[type=date]", count: 0
    end
  end

  test "changes the displayed date and dish at midnight in Japan" do
    yesterday_dish = Dish.create!(name: "味噌汁", category: :soup)
    FeedbackTarget.create!(dish: yesterday_dish, target_date: Date.yesterday)

    travel_to Time.utc(2026, 10, 7, 14, 59, 59)
    get new_reaction_url
    assert_response :success
    assert_select "time[datetime='2026-10-07']", text: "2026年10月7日"
    assert_select "main p", text: "対象料理：味噌汁（汁物）"

    travel_to Time.utc(2026, 10, 7, 15, 0, 0)
    get new_reaction_url
    assert_response :success
    assert_select "time[datetime='2026-10-08']", text: "2026年10月8日"
    assert_select "main p", text: "対象料理：カレー（主菜）"
  end

  test "only lists the logged in user's kindergarten classes even with another kindergarten's parameters" do
    other_kindergarten = Kindergarten.create!(name: "ひまわり幼稚園")
    other_classroom = other_kindergarten.classrooms.create!(name: "他園のクラス")

    get new_reaction_url, params: { kindergarten_id: other_kindergarten.id, classroom_id: other_classroom.id }

    assert_response :success
    assert_select "select[name=classroom_id] option", count: @classrooms.size + 1
    assert_select "select[name=classroom_id] option[value=?]", other_classroom.id, count: 0
    assert_select "select[name=classroom_id] option[selected]", count: 0
  end

  test "redirects logged out users to the kindergarten login without a flash alert" do
    delete kindergarten_logout_path

    get new_reaction_url

    assert_redirected_to kindergarten_login_url
    assert_nil flash[:alert]
  end

  test "redirects a user whose session no longer refers to an existing user" do
    @user.destroy!

    get new_reaction_url

    assert_redirected_to kindergarten_login_url
  end

  test "forbids center users without displaying the input page or adding a flash alert" do
    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "center-password" }

    get new_reaction_url

    assert_response :forbidden
    assert_empty response.body
    assert_nil flash[:alert]
    assert_equal user.id, request.session[:user_id]
  end

  test "handles an unset target without showing another day's dish or the later issue's guidance" do
    @feedback_target.destroy!
    FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)
    FeedbackTarget.create!(dish: @dish, target_date: Date.tomorrow)

    get new_reaction_url

    assert_response :success
    assert_select "time[datetime=?]", Date.current.iso8601
    assert_select ".reaction-entry-dish, main select, main form", count: 0
    assert_select "main", text: /まだ設定されていません/, count: 0
  end

  test "display and supplied class or reaction parameters never create or update reactions" do
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    original_attributes = reaction.attributes

    assert_no_difference "Reaction.count" do
      get new_reaction_url
      get new_reaction_url, params: { classroom_id: @classrooms.last.id, reaction: {
        classroom_id: @classrooms.first.id, feedback_target_id: @feedback_target.id,
        positive_count: 10, neutral_count: 10, negative_count: 10 } }
    end

    assert_response :success
    assert_equal original_attributes, reaction.reload.attributes
    assert_select "main input, main button, main form", count: 0
  end
end
