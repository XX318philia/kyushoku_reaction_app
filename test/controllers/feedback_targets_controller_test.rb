require "test_helper"

class FeedbackTargetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 8, 0, 30)
    @dish = Dish.create!(name: "カレー", category: :main_dish)
    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "center-password" }
  end

  test "displays today's date and an unselected dish form with names and all categories" do
    dishes = [ @dish,
      Dish.create!(name: "カレー", category: :side_dish),
      Dish.create!(name: "野菜スープ", category: :soup),
      Dish.create!(name: "ヨーグルト", category: :fruit_or_dessert) ]

    get new_feedback_target_url, params: { target_date: Date.yesterday }

    assert_response :success
    assert_select "title", text: "対象料理設定 | 給食リアクション"
    assert_select "time[datetime=?]", Date.current.iso8601, text: "2026年10月8日"
    assert_select "h2", text: "設定フォーム"
    assert_select "form[action=?][method=post]", feedback_targets_path do
      assert_select "label[for=feedback_target_dish_id]", text: "対象料理"
      assert_select "select[name=?]", "feedback_target[dish_id]" do
        assert_select "option[value='']", text: "料理を選択してください", count: 1
        assert_select "option[selected]", count: 0
        assert_select "option", count: 5
        dishes.zip([ "カレー（主菜）", "カレー（副菜）", "野菜スープ（汁物）", "ヨーグルト（フルーツ・デザート）" ]).each do |dish, label|
          assert_select "option[value=?]", dish.id, text: label, count: 1
        end
      end
      assert_select "input[type=submit][value=設定]", count: 1
    end
    assert_select "main select", count: 1
    assert_select "main input:not([type=hidden]):not([type=submit])", count: 0
    assert_select "[name=?]", "feedback_target[target_date]", count: 0
    assert_select "[role=alert]", count: 0
  end

  test "creates a feedback target for Date current and redirects to root" do
    assert_difference "FeedbackTarget.count", 1 do
      post feedback_targets_url, params: { feedback_target: { dish_id: @dish.id } }
    end

    assert_response :see_other
    assert_redirected_to root_url
    feedback_target = FeedbackTarget.find_by!(target_date: Date.current)
    assert_equal @dish, feedback_target.dish
    assert_equal Date.new(2026, 10, 8), feedback_target.target_date
  end

  test "accepts only dish id and ignores dates and other attributes supplied by the user" do
    timestamp = Time.utc(2000, 1, 1)

    assert_difference "FeedbackTarget.count", 1 do
      post feedback_targets_url, params: { target_date: Date.tomorrow, feedback_target: {
        dish_id: @dish.id, target_date: Date.yesterday, id: -1, created_at: timestamp, updated_at: timestamp } }
    end

    assert_redirected_to root_url
    feedback_target = FeedbackTarget.find_by!(target_date: Date.current)
    assert_equal @dish, feedback_target.dish
    assert_not_equal(-1, feedback_target.id)
    assert_not_equal timestamp, feedback_target.created_at
    assert_not_equal timestamp, feedback_target.updated_at
  end

  test "shows the current target without a new form when today's target exists" do
    FeedbackTarget.create!(dish: @dish, target_date: Date.current)

    get new_feedback_target_url

    assert_already_configured(@dish)
  end

  test "does not change today's target when another dish is posted after setting" do
    feedback_target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    other_dish = Dish.create!(name: "味噌汁", category: :soup)

    assert_no_difference "FeedbackTarget.count" do
      post feedback_targets_url, params: { feedback_target: { dish_id: other_dish.id } }
    end

    assert_already_configured(@dish)
    assert_equal @dish, feedback_target.reload.dish
  end

  test "a target on a different date does not prevent today's setting" do
    FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)

    get new_feedback_target_url

    assert_response :success
    assert_select "form[action=?]", feedback_targets_path, count: 1

    assert_difference "FeedbackTarget.count", 1 do
      post feedback_targets_url, params: { feedback_target: { dish_id: @dish.id } }
    end

    assert_redirected_to root_url
    assert FeedbackTarget.exists?(dish: @dish, target_date: Date.current)
  end

  test "shows a dish registration link and no usable form when no dishes exist" do
    @dish.destroy!

    get new_feedback_target_url

    assert_response :success
    assert_select "main p", text: "料理マスタが登録されていません。先に料理を登録してください"
    assert_select "main a[href=?]", new_dish_path, text: "料理マスタ登録", count: 1
    assert_select "main form", count: 0
    assert_select "main select, main input[type=submit]", count: 0
  end

  test "does not register a missing dish and displays the errors" do
    [ nil, "" ].each do |dish_id|
      assert_registration_failure(dish_id)
    end
  end

  test "does not register a nonexistent dish and displays the errors" do
    assert_registration_failure(Dish.maximum(:id) + 1)
  end

  test "a direct post with no dishes displays errors and the registration link" do
    @dish.destroy!

    assert_no_difference "FeedbackTarget.count" do
      post feedback_targets_url, params: { feedback_target: { dish_id: "" } }
    end

    assert_response :unprocessable_content
    assert_select "[role=alert] li", text: "Dish must exist"
    assert_select "main a[href=?]", new_dish_path, text: "料理マスタ登録"
    assert_select "main form", count: 0
  end

  test "shows the first target when a competing registration is detected by validation" do
    assert_competing_registration(validate: true)
  end

  test "shows the first target after an actual database unique constraint conflict" do
    assert_competing_registration(validate: false)
  end

  private

  def assert_registration_failure(dish_id)
    feedback_target = FeedbackTarget.new(dish_id: dish_id, target_date: Date.current)
    assert_not feedback_target.valid?

    assert_no_difference "FeedbackTarget.count" do
      post feedback_targets_url, params: { feedback_target: { dish_id: dish_id } }
    end

    assert_response :unprocessable_content
    assert_select "form[action=?]", feedback_targets_path, count: 1
    feedback_target.errors.full_messages.each do |message|
      assert_select "[role=alert] li", text: message, count: 1
    end
  end

  def assert_already_configured(dish)
    category_labels = { "main_dish" => "主菜", "side_dish" => "副菜", "soup" => "汁物", "fruit_or_dessert" => "フルーツ・デザート" }

    assert_response :success
    assert_select "time[datetime=?]", Date.current.iso8601
    assert_select "main p", text: "本日の対象料理は設定済みです", count: 1
    assert_select "main p", text: "対象料理：#{dish.name}（#{category_labels.fetch(dish.category)}）", count: 1
    assert_select "main form, main select, main input[type=submit]", count: 0
    assert_select "[role=alert]", count: 0
  end

  def assert_competing_registration(validate:)
    first_target = FeedbackTarget.new(dish: @dish, target_date: Date.current)
    other_dish = Dish.create!(name: "味噌汁", category: :soup)
    second_target = FeedbackTarget.new(dish: other_dish, target_date: Date.current)

    # 初回の存在確認後に先行登録を保存し、後続登録を検証する。
    # DB競合はsavepoint内で起こし、テスト全体のtransactionを保護する。
    second_target.define_singleton_method(:save) do
      first_target.save!
      FeedbackTarget.transaction(requires_new: true) { super(validate: validate) }
    end

    FeedbackTarget.define_singleton_method(:new) { |*| second_target }
    begin
      assert_difference "FeedbackTarget.count", 1 do
        post feedback_targets_url, params: { feedback_target: { dish_id: other_dish.id } }
      end
    ensure
      FeedbackTarget.singleton_class.remove_method(:new)
    end

    assert_already_configured(@dish)
    assert first_target.persisted?
    assert_not second_target.persisted?
    assert_equal first_target, FeedbackTarget.find_by!(target_date: Date.current)
  end
end
