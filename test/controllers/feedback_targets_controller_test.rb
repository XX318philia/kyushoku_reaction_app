require "test_helper"

class FeedbackTargetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 8, 0, 30)
    @dish = Dish.create!(name: "カレー", category: :main_dish)
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

  test "redirects kindergarten users to entry with an alert without creating or updating targets" do
    user = User.create!(login_id: "Sakura", password: "kindergarten-password",
      role: :kindergarten, kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
    post kindergarten_login_path, params: { login_id: user.login_id, password: "kindergarten-password" }

    get new_feedback_target_url
    assert_access_denied

    assert_no_difference "FeedbackTarget.count" do
      post feedback_targets_url, params: { feedback_target: { dish_id: @dish.id } }
    end
    assert_access_denied

    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    original_attributes = target.attributes
    other_dish = Dish.create!(name: "味噌汁", category: :soup)
    assert_no_difference "FeedbackTarget.count" do
      post feedback_targets_url, params: { feedback_target: { dish_id: other_dish.id } }
    end
    assert_access_denied
    assert_equal original_attributes, target.reload.attributes
    assert_equal user.id, request.session[:user_id]
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

  test "creates a feedback target for Date current and redirects to center results" do
    assert_difference "FeedbackTarget.count", 1 do
      post feedback_targets_url, params: { feedback_target: { dish_id: @dish.id } }
    end

    assert_response :see_other
    assert_redirected_to center_reaction_results_url
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

    assert_redirected_to center_reaction_results_url
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

    assert_redirected_to center_reaction_results_url
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

  test "only a configured target exposes the GET confirmation link" do
    get new_feedback_target_url
    assert_select "a", text: "本日の設定を取り消す", count: 0

    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    get new_feedback_target_url
    assert_select "h2", text: "設定フォーム"
    assert_select "a[href=?]", confirm_destroy_feedback_target_path(target), text: "本日の設定を取り消す"
  end

  test "confirmation and cancellation navigation preserve all records and show the deletion warning" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    create_cancellation_reactions(target)
    original_data = stored_data

    token = confirmation_token(target, target_date: Date.yesterday)

    assert_select "time[datetime=?]", Date.current.iso8601, text: "2026年10月8日"
    assert_select "main p", text: "対象料理：カレー（主菜）"
    assert_select "main p", text: "本日の対象料理とリアクション記録が削除されます。"
    assert_select "main p", text: "料理マスタは削除されません。"
    assert_select "main p", text: "この操作は元に戻せません。"
    assert_select "main p", text: "本当に、本日のフィードバック対象料理の設定を取り消しますか？", count: 0
    assert_select ".feedback-target-cancellation-date + .feedback-target-cancellation-dish", text: "対象料理：カレー（主菜）"
    assert_select "main", text: /6-c|flash|仕様について/, count: 0
    assert_select "form[action=?][method=post]", feedback_target_path(target) do
      assert_select "input[name=_method][value=delete]"
      assert_select "input[name=displayed_target][value=?]", token
    end
    assert_select "a[href=?]", new_feedback_target_path, text: "キャンセル"

    get new_feedback_target_url
    assert_already_configured(@dish)
    assert_equal original_data, stored_data
  end

  test "cancels a target with zero reactions and permits setting another dish" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    token = confirmation_token(target)

    assert_difference "FeedbackTarget.count", -1 do
      assert_no_difference "Reaction.count" do
        delete feedback_target_url(target), params: { displayed_target: token, target_date: Date.yesterday }
      end
    end

    assert_response :see_other
    assert_redirected_to new_feedback_target_url
    assert_equal "本日の対象料理を取り消しました", flash[:notice]
    follow_redirect!
    assert_select "h2 + [role=status]", text: "本日の対象料理を取り消しました"
    assert_select "form[action=?]", feedback_targets_path
    assert_select "a", text: "本日の設定を取り消す", count: 0

    other_dish = Dish.create!(name: "味噌汁", category: :soup)
    assert_difference "FeedbackTarget.count", 1 do
      post feedback_targets_url, params: { feedback_target: { dish_id: other_dish.id } }
    end
    assert_equal other_dish, FeedbackTarget.find_by!(target_date: Date.current).dish
  end

  test "cancellation removes only today's target and its reactions across kindergartens" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    reactions = create_cancellation_reactions(target)
    historical_target = FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)
    historical_reaction = Reaction.create!(classroom: reactions.first.classroom, feedback_target: historical_target,
      positive_count: 1, neutral_count: 0, negative_count: 0)
    retained_data = [ Dish, User, Kindergarten, Classroom ].map { |model| model.order(:id).map(&:attributes) }
    historical_data = [ historical_target.attributes, historical_reaction.attributes ]
    token = confirmation_token(target)

    assert_difference "FeedbackTarget.count", -1 do
      assert_difference "Reaction.count", -2 do
        delete feedback_target_url(target), params: { displayed_target: token }
      end
    end

    assert_redirected_to new_feedback_target_url
    assert_equal retained_data, [ Dish, User, Kindergarten, Classroom ].map { |model| model.order(:id).map(&:attributes) }
    assert_equal historical_data, [ historical_target.reload.attributes, historical_reaction.reload.attributes ]

    get center_reaction_results_url
    assert_select ".center-reaction-results-unset-notice"
    assert_select ".center-reaction-results-grid", count: 0
    user = User.find_by!(role: :kindergarten)
    post kindergarten_login_url, params: { login_id: user.login_id, password: "kindergarten-password" }
    get new_reaction_url, params: { classroom_id: reactions.first.classroom_id }
    assert_select ".reaction-entry-unset-notice"
    assert_select "main form", count: 0
  end

  test "a parent destroy abort restores reactions already destroyed and shows the failure under the heading" do
    assert_cancellation_failure(-> { throw :abort })
  end

  test "a dependent reaction destroy abort restores the entire target and reaction set" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    reactions = create_cancellation_reactions(target)
    token = confirmation_token(target)
    original_data = stored_data
    callback = -> { throw :abort if id == reactions.last.id }
    Reaction.set_callback(:destroy, :before, callback)
    begin
      delete feedback_target_url(target), params: { displayed_target: token }
    ensure
      Reaction.skip_callback(:destroy, :before, callback)
    end

    assert_failed_cancellation(original_data)
  end

  test "a database deletion error rolls back dependent deletes and returns the failure message" do
    assert_cancellation_failure(-> { raise ActiveRecord::InvalidForeignKey, "deletion rejected" })
  end

  test "rejects an old confirmation after the same target changes its dish" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    token = confirmation_token(target)
    other_dish = Dish.create!(name: "味噌汁", category: :soup)
    target.update!(dish: other_dish)
    original_data = stored_data

    delete feedback_target_url(target), params: { displayed_target: token }

    assert_stale_cancellation(original_data)
    follow_redirect!
    assert_select "h2 + [role=alert]", text: /設定が変更されたため/
    assert_select "main p", text: "対象料理：味噌汁（汁物）"
  end

  test "rejects an old confirmation after a target is replaced even with the same dish" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    token = confirmation_token(target)
    target.destroy!
    replacement = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    original_data = stored_data

    [ target.id, replacement.id ].each do |id|
      delete feedback_target_url(id), params: { displayed_target: token }
      assert_stale_cancellation(original_data)
    end
  end

  test "an old confirmation without a current target returns to the unset form with an alert" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    token = confirmation_token(target)
    target.destroy!
    original_data = stored_data

    delete feedback_target_url(target), params: { displayed_target: token }

    assert_stale_cancellation(original_data)
    follow_redirect!
    assert_select "h2 + [role=alert]", text: /設定が変更されたため/
    assert_select "form[action=?]", feedback_targets_path
    assert_select "a", text: "本日の設定を取り消す", count: 0
  end

  test "missing malformed tampered and foreign-purpose confirmation tokens never delete records" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    token = confirmation_token(target)
    foreign_token = Rails.application.message_verifier(:reaction_entry).generate([ Date.current.iso8601, target.id, @dish.id ])
    original_data = stored_data

    [ nil, "", "#{token}tampered", [], { id: target.id }, foreign_token ].each do |invalid_token|
      delete feedback_target_url(target), params: { displayed_target: invalid_token }
      assert_stale_cancellation(original_data)
    end
  end

  test "cannot confirm or cancel a past target even with a signed token and a supplied date" do
    historical_target = FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)
    today_target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    token = Rails.application.message_verifier(:feedback_target_cancellation).generate(
      [ Date.yesterday.iso8601, historical_target.id, @dish.id ])
    original_data = stored_data

    get confirm_destroy_feedback_target_url(historical_target), params: { target_date: Date.yesterday }
    assert_stale_cancellation(original_data)
    delete feedback_target_url(historical_target), params: { displayed_target: token, target_date: Date.yesterday }
    assert_stale_cancellation(original_data)
    assert FeedbackTarget.exists?(today_target.id)
  end

  test "the server date rejects yesterday's confirmation after midnight" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    token = confirmation_token(target)
    travel_to Time.zone.local(2026, 10, 9, 0, 1)
    original_data = stored_data

    delete feedback_target_url(target), params: { displayed_target: token, target_date: target.target_date }

    assert_stale_cancellation(original_data)
    follow_redirect!
    assert_select "time[datetime=?]", "2026-10-09"
    assert_select "form[action=?]", feedback_targets_path
  end

  test "rejects confirmation for a missing target without writes" do
    original_data = stored_data
    get confirm_destroy_feedback_target_url(-1)

    assert_stale_cancellation(original_data)
    follow_redirect!
    assert_select "h2 + [role=alert]", text: /設定が変更されたため/
  end

  test "kindergarten users cannot view confirmations or cancel targets" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    create_cancellation_reactions(target)
    token = confirmation_token(target)
    user = User.find_by!(role: :kindergarten)
    post kindergarten_login_url, params: { login_id: user.login_id, password: "kindergarten-password" }
    original_data = stored_data

    get confirm_destroy_feedback_target_url(target)
    assert_access_denied
    delete feedback_target_url(target), params: { displayed_target: token }
    assert_access_denied
    assert_equal original_data, stored_data
  end

  test "logged out and deleted session users cannot view confirmations or cancel targets" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    create_cancellation_reactions(target)
    token = confirmation_token(target)

    [ :logged_out, :deleted ].each do |state|
      post center_login_url, params: { login_id: @user.login_id, password: "center-password" }
      state == :logged_out ? delete(center_logout_url) : @user.destroy!
      original_data = stored_data

      get confirm_destroy_feedback_target_url(target)
      assert_response :see_other
      assert_redirected_to center_login_url
      assert_nil flash[:alert]
      delete feedback_target_url(target), params: { displayed_target: token }
      assert_response :see_other
      assert_redirected_to center_login_url
      assert_nil flash[:alert]
      assert_equal original_data, stored_data
    end
  end

  private

  def confirmation_token(target, **params)
    get confirm_destroy_feedback_target_url(target), params: params
    assert_response :success
    css_select("input[name=displayed_target]").first["value"]
  end

  def create_cancellation_reactions(target)
    kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    other_kindergarten = Kindergarten.create!(name: "ひまわり幼稚園")
    User.create!(login_id: "SakuraCancel", password: "kindergarten-password", role: :kindergarten, kindergarten: kindergarten)
    [ kindergarten, other_kindergarten ].map do |school|
      classroom = school.classrooms.create!(name: "年少")
      Reaction.create!(classroom: classroom, feedback_target: target, positive_count: 2, neutral_count: 1, negative_count: 0)
    end
  end

  def stored_data
    [ Reaction, FeedbackTarget, Dish, User, Kindergarten, Classroom ].map { |model| model.order(:id).map(&:attributes) }
  end

  def assert_stale_cancellation(original_data)
    assert_response :see_other
    assert_redirected_to new_feedback_target_url
    assert_match(/設定が変更されたため、取り消せませんでした/, flash[:alert])
    assert_equal original_data, stored_data
  end

  def assert_cancellation_failure(failure_callback)
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    create_cancellation_reactions(target)
    original_data = stored_data
    token = confirmation_token(target)
    deleted_reaction_count = nil
    callback = -> do
      deleted_reaction_count = reactions.count
      instance_exec(&failure_callback)
    end
    FeedbackTarget.set_callback(:destroy, :before, callback)
    begin
      delete feedback_target_url(target), params: { displayed_target: token }
    ensure
      FeedbackTarget.skip_callback(:destroy, :before, callback)
    end

    assert_equal 0, deleted_reaction_count, "The failure must occur after dependent reactions have been deleted"
    assert_failed_cancellation(original_data)
  end

  def assert_failed_cancellation(original_data)
    assert_response :see_other
    assert_redirected_to new_feedback_target_url
    assert_equal "取り消しに失敗しました", flash[:alert]
    assert_equal original_data, stored_data
    follow_redirect!
    assert_select "h2 + [role=alert]", text: "取り消しに失敗しました"
    assert_select "main p", text: "本日のフィードバック対象料理は、既に設定済みです。"
  end

  def assert_login_required
    get new_feedback_target_url
    assert_response :see_other
    assert_redirected_to center_login_url
    assert_nil flash[:alert]

    assert_no_difference "FeedbackTarget.count" do
      post feedback_targets_url, params: { feedback_target: { dish_id: @dish.id } }
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
    assert_select "main p", text: "本日のフィードバック対象料理は、既に設定済みです。", count: 1
    assert_select "main p", text: "対象料理：#{dish.name}（#{category_labels.fetch(dish.category)}）", count: 1
    assert_select ".feedback-target-setting-date + .feedback-target-setting-dish", text: "対象料理：#{dish.name}（#{category_labels.fetch(dish.category)}）"
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
