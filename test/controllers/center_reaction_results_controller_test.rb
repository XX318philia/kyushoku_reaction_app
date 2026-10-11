require "test_helper"

class CenterReactionResultsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 8, 0, 30)
    @user = User.create!(login_id: "CenterResults", password: "center-password", role: :center)
    @kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    @classrooms = [ "年少", "年中" ].map { |name| @kindergarten.classrooms.create!(name: name) }
    @dish = Dish.create!(name: "カレー", category: :main_dish)
    @feedback_target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    post center_login_path, params: { login_id: @user.login_id, password: "center-password" }
  end

  test "shows today's target and all kindergartens and classes regardless of supplied filters" do
    create_reaction(@classrooms.first, [ 2, 1, 0 ])
    create_reaction(@classrooms.last, [ 1, 1, 1 ])
    other_classroom = Kindergarten.create!(name: "ひまわり幼稚園").classrooms.create!(name: "年少")
    create_reaction(other_classroom, [ 1, 0, 2 ])
    yesterday_target = FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)
    other_dish = Dish.create!(name: "味噌汁", category: :soup)
    tomorrow_target = FeedbackTarget.create!(dish: other_dish, target_date: Date.tomorrow)
    [ yesterday_target, tomorrow_target ].each do |target|
      create_reaction(@classrooms.first, [ 99, 99, 99 ], target: target)
    end

    [ {}, { classroom_id: @classrooms.first.id }, { classroom_id: other_classroom.id },
      { kindergarten_id: @kindergarten.id, target_date: Date.yesterday, feedback_target_id: yesterday_target.id },
      { target_date: Date.tomorrow, dish_id: other_dish.id } ].each do |filters|
      get center_reaction_results_url, params: filters

      assert_response :success
      assert_select "title", text: "本日の集計結果 | 給食リアクション"
      assert_select "h2", text: "本日の集計結果"
      assert_select "time[datetime='2026-10-08']", text: "2026年10月8日"
      assert_select ".center-reaction-results-dish", text: "対象料理：カレー"
      assert_results([ "4人 / 44.4%", "2人 / 22.2%", "3人 / 33.3%" ], 9)
      assert_select "main", text: /味噌汁/, count: 0
      assert_select "main input, main select, main form", count: 0
    end
  end

  test "rounds percentages to one decimal and displays zero and one hundred percent" do
    reaction = create_reaction(@classrooms.first, [ 1, 5, 0 ])

    get center_reaction_results_url
    assert_results([ "1人 / 16.7%", "5人 / 83.3%", "0人 / 0.0%" ], 6)

    [ [ 1, 0, 0 ], [ 0, 1, 0 ], [ 0, 0, 1 ] ].each do |counts|
      reaction.update!(%i[ positive_count neutral_count negative_count ].zip(counts).to_h)
      get center_reaction_results_url
      assert_results(counts.map { |count| "#{count}人 / #{count == 1 ? '100.0%' : '0.0%'}" }, 1)
    end
  end

  test "shows zero people and dashes when the target has no reactions" do
    get center_reaction_results_url

    assert_response :success
    assert_select ".center-reaction-results-dish", text: "対象料理：カレー"
    assert_results([ "0人 / -", "0人 / -", "0人 / -" ], 0)
    assert_select ".center-reaction-results-unset-notice", count: 0
    assert_nil @feedback_target.reaction_summary[:positive_percentage]
  end

  test "shows only user facing reload guidance" do
    get center_reaction_results_url

    assert_select ".center-reaction-results-notes", text: "※ 最新の集計を確認したい場合は、ページを再読み込みしてください。", count: 1
    assert_select "main", text: /計算方法の不整合|過去日閲覧はMVP対象外/, count: 0
  end

  test "shows today's date and exact unset guidance without another day's dish or totals" do
    @feedback_target.update!(target_date: Date.yesterday)
    create_reaction(@classrooms.first, [ 2, 1, 0 ])

    get center_reaction_results_url, params: { target_date: Date.yesterday, feedback_target_id: @feedback_target.id }

    assert_response :success
    assert_select "h2", text: "本日の集計結果"
    assert_select "time[datetime='2026-10-08']", text: "2026年10月8日"
    assert_select ".center-reaction-results-unset-notice p", count: 2
    assert_select ".center-reaction-results-unset-notice p:first-child", text: "本日のフィードバック対象料理は、まだ設定されていません。"
    assert_select ".center-reaction-results-unset-notice p:last-child", text: "『対象料理設定画面』で設定を完了させてください。"
    assert_select ".center-reaction-results-dish, .center-reaction-results-grid, .center-reaction-results-notes", count: 0
    assert_select "main", text: /カレー/, count: 0
  end

  test "uses Date current across midnight in Japan" do
    yesterday_target = FeedbackTarget.create!(dish: Dish.create!(name: "味噌汁", category: :soup), target_date: Date.yesterday)
    create_reaction(@classrooms.first, [ 0, 1, 0 ], target: yesterday_target)

    travel_to Time.utc(2026, 10, 7, 14, 59, 59)
    get center_reaction_results_url
    assert_select "time[datetime='2026-10-07']", text: "2026年10月7日"
    assert_select ".center-reaction-results-dish", text: "対象料理：味噌汁"
    assert_results([ "0人 / 0.0%", "1人 / 100.0%", "0人 / 0.0%" ], 1)

    travel_to Time.utc(2026, 10, 7, 15)
    get center_reaction_results_url
    assert_select "time[datetime='2026-10-08']", text: "2026年10月8日"
    assert_select ".center-reaction-results-dish", text: "対象料理：カレー"
    assert_results([ "0人 / -", "0人 / -", "0人 / -" ], 0)
  end

  test "login and the header open center results while root remains the home page" do
    assert_redirected_to center_reaction_results_url
    follow_redirect!
    assert_response :success
    assert_select "main.center-reaction-results", count: 1

    get root_url
    assert_response :success
    assert_select "a[href=?]", kindergarten_login_path, text: "幼稚園様はこちら"
    assert_select "header a[href=?]", center_reaction_results_path, text: "当日集計結果", count: 1

    get center_reaction_results_url
    assert_response :success
    assert_select "header nav[aria-label=?]", "給食センター用ナビゲーション", count: 1
  end

  test "setting a target redirects to results and displays the configured dish" do
    @feedback_target.destroy!

    post feedback_targets_url, params: { feedback_target: { dish_id: @dish.id } }

    assert_response :see_other
    assert_redirected_to center_reaction_results_url
    follow_redirect!
    assert_response :success
    assert_select ".center-reaction-results-dish", text: "対象料理：カレー"
    assert_results([ "0人 / -", "0人 / -", "0人 / -" ], 0)
  end

  test "redirects logged out and deleted users and forbids kindergarten users without flash alerts" do
    @user.destroy!
    get center_reaction_results_url
    assert_redirected_to center_login_url
    assert_nil flash[:alert]

    delete center_logout_path
    get center_reaction_results_url
    assert_redirected_to center_login_url
    assert_nil flash[:alert]

    user = User.create!(login_id: "ResultsSakura", password: "kindergarten-password",
      role: :kindergarten, kindergarten: @kindergarten)
    post kindergarten_login_path, params: { login_id: user.login_id, password: "kindergarten-password" }
    get center_reaction_results_url
    assert_response :forbidden
    assert_empty response.body
    assert_nil flash[:alert]
  end

  test "viewing results preserves all stored data and reloads reflect later registrations and updates" do
    reaction = create_reaction(@classrooms.first, [ 2, 1, 0 ])
    original_data = stored_data

    2.times do
      get center_reaction_results_url
      assert_results([ "2人 / 66.7%", "1人 / 33.3%", "0人 / 0.0%" ], 3)
    end
    assert_equal original_data, stored_data

    reaction.update!(positive_count: 4)
    create_reaction(@classrooms.last, [ 0, 1, 2 ])
    updated_data = stored_data
    get center_reaction_results_url
    assert_results([ "4人 / 50.0%", "2人 / 25.0%", "2人 / 25.0%" ], 8)
    assert_equal updated_data, stored_data
  end

  private

  def create_reaction(classroom, counts, target: @feedback_target)
    Reaction.create!({ classroom: classroom, feedback_target: target }.merge(
      %i[ positive_count neutral_count negative_count ].zip(counts).to_h))
  end

  def stored_data
    [ Reaction, FeedbackTarget, Dish, Classroom, Kindergarten, User ].map { |model| model.order(:id).map(&:attributes) }
  end

  def assert_results(values, total)
    labels = [ "美味しそうに食べていた", "普通・どちらでもない", "苦手そうに食べていた" ]
    assert_select ".center-reaction-results-count", count: 3
    assert_select ".center-reaction-results-count" do |rows|
      rows.zip(labels, values).each do |row, label, value|
        assert_select row, ".center-reaction-results-label", text: label, count: 1
        assert_select row, ".center-reaction-results-value", text: value, count: 1
      end
    end
    assert_select ".center-reaction-results-total", count: 1 do
      assert_select ".center-reaction-results-label", text: "観察対象人数", count: 1
      assert_select ".center-reaction-results-value", text: "#{total}人", count: 1
    end
  end
end
