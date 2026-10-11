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
    get new_reaction_url
    @displayed_target = css_select("input[name=displayed_target]").first["value"]
  end

  test "displays today's date and dish with a class selector and three initial reaction counts" do
    get new_reaction_url

    assert_response :success
    assert_select "title", text: "リアクション入力 | 給食リアクション"
    assert_select "head link[rel=stylesheet][data-turbo-track=dynamic][href=?]",
      "https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400&display=swap", count: 1
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
    assert_select "main form[action=?][method=get]", new_reaction_path, count: 1 do
      assert_select "select#classroom_id", count: 1
      assert_select "input[type=submit][value=決定]", count: 1
      assert_select "input[type=number], input[name=displayed_target]", count: 0
    end
    assert_select "main input[type=number]", count: 3
    { positive_count: "美味しそうに食べていた", neutral_count: "普通・どちらでもない", negative_count: "苦手そうに食べていた" }.each do |attribute, label|
      assert_select ".reaction-entry-count" do
        assert_select "label[for=?]", "reaction_#{attribute}", text: label, count: 1
        assert_select "input#reaction_#{attribute}[name=?][type=number][value='0'][min='0'][step='1'][required]:not([disabled]):not([readonly])",
          "reaction[#{attribute}]", count: 1
      end
    end
    assert_select "main form[action=?][method=post]", reactions_path, count: 1 do
      assert_select "select, input[name=_method]", count: 0
      assert_select "input#loaded_classroom_id[type=hidden][name=classroom_id]", count: 1 do |fields|
        assert_empty fields.first["value"].to_s
      end
    end
    assert_select "input[name=displayed_target][type=hidden]", count: 1
    assert_select "input[type=submit][value=登録]", count: 1
    assert_select ".reaction-entry-constraint", text: "入力制約：0以上の整数"
    assert_select ".reaction-entry-unset-notice", count: 0
    assert_select ".reaction-entry-loaded-classroom", count: 0
  end

  test "displays Japanese labels for all four dish categories" do
    { main_dish: "主菜", side_dish: "副菜", soup: "汁物", fruit_or_dessert: "フルーツ・デザート" }.each do |category, label|
      @dish.update!(category: category)

      get new_reaction_url

      assert_response :success
      assert_select "main p", text: "対象料理：カレー（#{label}）", count: 1
    end
  end

  test "loads each saved count including zeros for the selected class using a POST update form" do
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 1, neutral_count: 2, negative_count: 0)
    Reaction.create!(classroom: @classrooms.last, feedback_target: @feedback_target,
      positive_count: 9, neutral_count: 8, negative_count: 7)

    [ [ 0, 1, 2 ], [ 2, 0, 1 ], [ 1, 2, 0 ] ].each do |counts|
      reaction.update!(%i[ positive_count neutral_count negative_count ].zip(counts).to_h)
      original_attributes = reaction.attributes

      assert_no_difference "Reaction.count" do
        get new_reaction_url, params: { classroom_id: @classrooms.first.id }
      end

      assert_response :success
      assert_reaction_counts(counts)
      assert_select "select#classroom_id option[selected][value=?]", @classrooms.first.id
      assert_select "main form[action=?][method=post]", reactions_path, count: 1 do
        assert_select "input#loaded_classroom_id[value=?]", @classrooms.first.id
        assert_select ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）", count: 1
        assert_select ".reaction-entry-loaded-classroom + .reaction-entry-count #reaction_positive_count", count: 1
        assert_select "input[name=_method]", count: 0
        assert_select "input[type=submit][value=更新]", count: 1
        assert_select "input[name=displayed_reaction][type=hidden]", count: 1
      end
      assert_select "h2", text: "編集フォーム"
      assert_equal original_attributes, reaction.reload.attributes
    end
  end

  test "shows zeros for an unregistered class and for an unselected class despite other saved reactions" do
    Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)

    [ @classrooms.last.id, nil, "" ].each do |id|
      get new_reaction_url, params: { classroom_id: id }

      assert_response :success
      assert_reaction_counts([ 0, 0, 0 ])
      assert_select "h2", text: "入力フォーム"
      assert_select "input[type=submit][value=登録]", count: 1
      assert_select "input[name=displayed_reaction]", count: 0
      assert_select "input#loaded_classroom_id", count: 1 do |fields|
        assert_equal id.to_s, fields.first["value"].to_s
      end
      if id == @classrooms.last.id
        assert_select ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.last.name}）", count: 1
      else
        assert_select ".reaction-entry-loaded-classroom", count: 0
      end
    end
  end

  test "does not load other kindergarten reactions or malformed and nonexistent classroom ids" do
    other_kindergarten = Kindergarten.create!(name: "ひまわり幼稚園")
    other_classroom = other_kindergarten.classrooms.create!(name: "他園のクラス")
    Reaction.create!(classroom: other_classroom, feedback_target: @feedback_target,
      positive_count: 9, neutral_count: 8, negative_count: 7)
    Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)

    [ other_classroom.id, Classroom.maximum(:id) + 1, "invalid", "#{@classrooms.first.id}invalid", "1.5",
      [ @classrooms.first.id ], { id: @classrooms.first.id } ].each do |id|
      get new_reaction_url, params: { classroom_id: id }

      assert_response :success
      assert_reaction_counts([ 0, 0, 0 ])
      assert_select "select#classroom_id option[selected]", count: 0
      assert_select ".reaction-entry-loaded-classroom", count: 0
      assert_select "input#loaded_classroom_id", count: 1 do |fields|
        assert_empty fields.first["value"].to_s
      end
    end
  end

  test "only loads today's reaction even when past or future targets and counts are supplied" do
    [ Date.yesterday, Date.tomorrow ].each do |date|
      target = FeedbackTarget.create!(dish: @dish, target_date: date)
      reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: target,
        positive_count: 9, neutral_count: 8, negative_count: 7)

      get new_reaction_url, params: { classroom_id: @classrooms.first.id, target_date: date,
        feedback_target_id: target.id, reaction: { id: reaction.id, positive_count: 9, neutral_count: 8, negative_count: 7 } }

      assert_response :success
      assert_reaction_counts([ 0, 0, 0 ])
      assert_select "time[datetime=?]", Date.current.iso8601
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

  test "displays two guidance paragraphs for an unset target even when other days have targets" do
    @feedback_target.destroy!
    yesterday_dish = Dish.create!(name: "肉じゃが", category: :main_dish)
    tomorrow_dish = Dish.create!(name: "野菜スープ", category: :soup)
    yesterday_target = FeedbackTarget.create!(dish: yesterday_dish, target_date: Date.yesterday)
    FeedbackTarget.create!(dish: tomorrow_dish, target_date: Date.tomorrow)
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: yesterday_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    original_attributes = reaction.attributes

    assert_no_difference "Reaction.count" do
      get new_reaction_url, params: { target_date: Date.yesterday, classroom_id: @classrooms.last.id,
        reaction: { feedback_target_id: yesterday_target.id, positive_count: 10, neutral_count: 10, negative_count: 10 } }
    end

    assert_response :success
    assert_select "h2", text: "入力フォーム"
    assert_select "time[datetime='2026-10-08']", text: "2026年10月8日"
    assert_select ".reaction-entry-unset-notice" do
      assert_select "p", count: 2
      assert_select "p:first-child", text: "本日のフィードバック対象料理はまだ設定されていません。"
      assert_select "p:last-child", text: "給食センター側で設定されると、リアクションを入力できるようになります。"
    end
    assert_select ".reaction-entry-dish, main label, main select, main input, main button, main form", count: 0
    assert_select "main", text: /肉じゃが|野菜スープ/, count: 0
    assert_equal original_attributes, reaction.reload.attributes
  end

  test "displays the normal page after today's target is set and the page is requested again" do
    @feedback_target.destroy!

    assert_no_difference "Reaction.count" do
      get new_reaction_url
      assert_response :success
      assert_select ".reaction-entry-unset-notice p", count: 2

      FeedbackTarget.create!(dish: @dish, target_date: Date.current)

      get new_reaction_url
      assert_response :success
      assert_select ".reaction-entry-unset-notice", count: 0
      assert_select "h2", text: "入力フォーム"
      assert_select "time[datetime='2026-10-08']", text: "2026年10月8日"
      assert_select ".reaction-entry-dish", text: "対象料理：カレー（主菜）"
      assert_select "select[name=classroom_id] option", count: @classrooms.size + 1
      assert_select "main input[type=number][value='0']", count: 3
      assert_select "main form[action=?][method=post]", reactions_path, count: 1
      assert_select "main input[type=submit][value=登録]", count: 1
    end
  end

  test "display and supplied class or reaction parameters never create or update reactions" do
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    original_attributes = reaction.attributes

    assert_no_difference "Reaction.count" do
      get new_reaction_url
      get new_reaction_url, params: { classroom_id: @classrooms.first.id, reaction: {
        positive_count: 10, neutral_count: 10, negative_count: 10 } }
      assert_reaction_counts([ 2, 1, 0 ])
      get new_reaction_url, params: { classroom_id: @classrooms.last.id, reaction: {
        classroom_id: @classrooms.first.id, feedback_target_id: @feedback_target.id,
        positive_count: 10, neutral_count: 10, negative_count: 10 } }
    end

    assert_response :success
    assert_equal original_attributes, reaction.reload.attributes
    assert_select "main input[type=number][value='0']", count: 3
    assert_select "main form[action=?][method=post]", reactions_path, count: 1
    assert_select "main input[type=submit][value=登録]", count: 1
  end

  test "creates a reaction for the selected class and today's target and shows the success flash" do
    assert_difference "Reaction.count", 1 do
      post reactions_url, params: registration_params
    end

    assert_response :see_other
    assert_redirected_to reactions_url
    reaction = Reaction.last
    assert_equal @classrooms.first, reaction.classroom
    assert_equal @feedback_target, reaction.feedback_target
    assert_equal [ 12, 3, 1 ], [ reaction.positive_count, reaction.neutral_count, reaction.negative_count ]
    assert_equal "登録が成功しました", flash[:notice]

    follow_redirect!
    assert_response :success
    assert_select "[role=status]", text: "登録が成功しました"
    assert_select "h2", text: "本日の集計結果"
    assert_select ".reaction-results-count .reaction-results-value", text: "12人 / 75.0%"
    assert_select "main input, main select", count: 0

    get new_reaction_url
    assert_select "[role=status]", count: 0
  end

  test "allows zero counts in individual fields when at least one child is recorded" do
    assert_difference "Reaction.count", 1 do
      post reactions_url, params: registration_params.merge(reaction: {
        positive_count: "0", neutral_count: "1", negative_count: "0" })
    end

    assert_redirected_to reactions_url
    assert_equal [ 0, 1, 0 ], Reaction.last.attributes.values_at("positive_count", "neutral_count", "negative_count")
  end

  test "does not create a reaction when logged out or the session user has been deleted" do
    @user.destroy!

    assert_no_difference "Reaction.count" do
      post reactions_url, params: registration_params
    end
    assert_redirected_to kindergarten_login_url

    delete kindergarten_logout_path
    assert_no_difference "Reaction.count" do
      post reactions_url, params: registration_params
    end
    assert_redirected_to kindergarten_login_url
    assert_nil flash[:alert]
  end

  test "forbids reaction registration from a center user" do
    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "center-password" }

    assert_no_difference "Reaction.count" do
      post reactions_url, params: registration_params
    end

    assert_response :forbidden
    assert_empty response.body
    assert_nil flash[:alert]
  end

  test "rejects missing nonexistent malformed and other kindergarten classroom ids" do
    other_kindergarten = Kindergarten.create!(name: "ひまわり幼稚園")
    other_classroom = other_kindergarten.classrooms.create!(name: "他園のクラス")

    [ nil, "", "invalid", "#{@classrooms.first.id}invalid", "1.5", Classroom.maximum(:id) + 1, other_classroom.id ].each do |id|
      assert_no_difference "Reaction.count" do
        post reactions_url, params: registration_params.merge(classroom_id: id, reaction: {
          classroom_id: @classrooms.first.id, positive_count: "12", neutral_count: "3", negative_count: "1" })
      end

      assert_response :unprocessable_content
      assert_select "[role=alert] li", text: "担当クラスを選択してください。"
      assert_select ".reaction-entry-loaded-classroom", count: 0
      assert_select "select#classroom_id option[selected]", count: 0
      assert_select "select#classroom_id option[value=?]", other_classroom.id, count: 0
      assert_select "#reaction_positive_count[value='12']"
    end
  end

  test "never saves when today's target is unset even when another target is supplied" do
    @feedback_target.destroy!
    yesterday_target = FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)

    assert_no_difference "Reaction.count" do
      post reactions_url, params: registration_params.merge(reaction: {
        feedback_target_id: yesterday_target.id, target_date: Date.yesterday,
        positive_count: "12", neutral_count: "3", negative_count: "1" })
    end

    assert_response :unprocessable_content
    assert_select "[role=alert] li", text: "本日のフィードバック対象料理はまだ設定されていません。"
    assert_select ".reaction-entry-unset-notice p", count: 2
    assert_select "main form, main input", count: 0
  end

  test "ignores supplied dates target ids classroom ids and timestamps as save destinations" do
    yesterday_target = FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)
    timestamp = Time.utc(2000, 1, 1)

    assert_difference "Reaction.count", 1 do
      post reactions_url, params: registration_params.merge(target_date: Date.yesterday,
        feedback_target_id: yesterday_target.id, kindergarten_id: -1, reaction: {
          classroom_id: @classrooms.last.id, feedback_target_id: yesterday_target.id, target_date: Date.yesterday,
          id: -1, created_at: timestamp, updated_at: timestamp,
          positive_count: "12", neutral_count: "3", negative_count: "1" })
    end

    assert_redirected_to reactions_url
    reaction = Reaction.last
    assert_equal @classrooms.first, reaction.classroom
    assert_equal @feedback_target, reaction.feedback_target
    assert_not_equal(-1, reaction.id)
    assert_not_equal timestamp, reaction.created_at
    assert_not_equal timestamp, reaction.updated_at
  end

  test "rejects invalid counts in each field and retains the original values and selected class" do
    %i[ positive_count neutral_count negative_count ].each do |attribute|
      [ nil, "", "-1", "1.5", "1.0", "abc", "12abc" ].each do |value|
        counts = registration_params[:reaction].merge(attribute => value)

        assert_no_difference "Reaction.count" do
          post reactions_url, params: registration_params.merge(reaction: counts)
        end

        assert_response :unprocessable_content
        assert_select ".alert.alert-danger[role=alert] li", minimum: 1
        assert_select "select#classroom_id option[selected][value=?]", @classrooms.first.id
        assert_select ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）", count: 1
        counts.each do |name, input|
          assert_select "input#reaction_#{name}", count: 1 do |fields|
            assert_equal input.to_s, fields.first["value"].to_s
          end
        end
      end
    end
  end

  test "rejects an entirely missing count payload as an input error" do
    assert_no_difference "Reaction.count" do
      post reactions_url, params: registration_params.except(:reaction)
    end

    assert_response :unprocessable_content
    assert_select "[role=alert] li", count: 3
    assert_select "main input[type=number]", count: 3 do |fields|
      fields.each { |field| assert_empty field["value"].to_s }
    end
  end

  test "rejects all zero counts with the existing model's error" do
    assert_no_difference "Reaction.count" do
      post reactions_url, params: registration_params.merge(reaction: {
        positive_count: "0", neutral_count: "0", negative_count: "0" })
    end

    assert_response :unprocessable_content
    assert_select "[role=alert] li", text: "リアクション人数を1人以上入力してください"
    assert_select "main input[type=number][value='0']", count: 3
    assert_select "select#classroom_id option[selected][value=?]", @classrooms.first.id
    assert_select ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）", count: 1
  end

  test "an unregistered form cannot overwrite a reaction registered before its submission" do
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    original_attributes = reaction.attributes
    get new_reaction_url, params: { classroom_id: @classrooms.first.id }
    assert_reaction_counts([ 2, 1, 0 ])

    assert_no_difference "Reaction.count" do
      post reactions_url, params: registration_params
    end

    assert_already_registered
    assert_equal original_attributes, reaction.reload.attributes
    assert_select "#reaction_positive_count[value='12']"
    assert_select ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）", count: 1
    assert_select "h2", text: "入力フォーム"
    assert_select "input[type=submit][value=登録]", count: 1
    assert_select "input[name=displayed_reaction]", count: 0
  end

  test "updates loaded counts without changing the count id or created timestamp and resets the selected class" do
    reaction = saved_reaction
    original_id = reaction.id
    original_created_at = reaction.created_at
    original_updated_at = reaction.updated_at
    update_params = editing_params(reaction)
    travel 1.minute

    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params
    end

    assert_response :see_other
    assert_redirected_to reactions_url
    assert_equal "登録内容を更新しました", flash[:notice]
    assert_equal [ 12, 3, 1 ], reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
    assert_equal original_id, reaction.id
    assert_equal original_created_at, reaction.created_at
    assert_operator reaction.updated_at, :>, original_updated_at

    follow_redirect!
    assert_response :success
    assert_select "[role=status]", text: "登録内容を更新しました"
    assert_select "h2", text: "本日の集計結果"
    assert_select ".reaction-results-count .reaction-results-value", text: "12人 / 75.0%"
    assert_select "main input, main select", count: 0

    get new_reaction_url
    assert_select "[role=status]", count: 0
    assert_select "h2", text: "入力フォーム"
    assert_select "select#classroom_id option[selected]", count: 0
    assert_select ".reaction-entry-loaded-classroom, input[name=displayed_reaction]", count: 0
    assert_reaction_counts([ 0, 0, 0 ])
  end

  test "allows repeated editing and zeros in individual updated fields" do
    reaction = saved_reaction
    update_params = editing_params(reaction)

    [ [ 0, 4, 0 ], [ 5, 0, 0 ], [ 0, 0, 6 ] ].each do |counts|
      assert_no_difference "Reaction.count" do
        post reactions_url, params: update_params.merge(reaction: %i[ positive_count neutral_count negative_count ].zip(counts).to_h)
      end

      assert_redirected_to reactions_url
      assert_equal counts, reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
    end
  end

  test "rejects invalid updated counts without modifying saved data and retains the editing form" do
    reaction = saved_reaction
    original_attributes = reaction.attributes
    update_params = editing_params(reaction)

    %i[ positive_count neutral_count negative_count ].each do |attribute|
      [ nil, "", "-1", "1.5", "1.0", "abc", "12abc" ].each do |value|
        counts = update_params[:reaction].merge(attribute => value)

        assert_no_difference "Reaction.count" do
          post reactions_url, params: update_params.merge(reaction: counts)
        end

        assert_response :unprocessable_content
        assert_equal original_attributes, reaction.reload.attributes
        assert_editing_error(reaction, update_params[:displayed_reaction])
        counts.each do |name, input|
          assert_select "input#reaction_#{name}", count: 1 do |fields|
            assert_equal input.to_s, fields.first["value"].to_s
          end
        end
      end
    end
  end

  test "rejects missing updated fields instead of filling them with saved counts" do
    reaction = saved_reaction
    original_attributes = reaction.attributes
    update_params = editing_params(reaction)

    %i[ positive_count neutral_count negative_count ].each do |attribute|
      assert_no_difference "Reaction.count" do
        post reactions_url, params: update_params.merge(reaction: update_params[:reaction].except(attribute))
      end

      assert_response :unprocessable_content
      assert_equal original_attributes, reaction.reload.attributes
      assert_editing_error(reaction, update_params[:displayed_reaction])
      assert_select "input#reaction_#{attribute}" do |fields|
        assert_empty fields.first["value"].to_s
      end
    end

    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params.except(:reaction)
    end
    assert_response :unprocessable_content
    assert_equal original_attributes, reaction.reload.attributes
    assert_editing_error(reaction, update_params[:displayed_reaction])
    assert_select "[role=alert] li", count: 3
    assert_select "main input[type=number]" do |fields|
      fields.each { |field| assert_empty field["value"].to_s }
    end
  end

  test "rejects JSON false and nonscalar updated counts using the existing validation" do
    reaction = saved_reaction
    original_attributes = reaction.attributes
    update_params = editing_params(reaction)

    %i[ positive_count neutral_count negative_count ].each do |attribute|
      [ false, [ 1 ], { value: 1 } ].each do |value|
        assert_no_difference "Reaction.count" do
          post reactions_url, params: update_params.merge(classroom_id: reaction.classroom_id.to_s,
            reaction: update_params[:reaction].merge(attribute => value)), as: :json, headers: { "Accept" => "text/html" }
        end
        assert_response :unprocessable_content
        assert_equal original_attributes, reaction.reload.attributes
        assert_editing_error(reaction, update_params[:displayed_reaction])
      end
    end
  end

  test "rejects all zero updated counts and permits a corrected submission from the error page" do
    reaction = saved_reaction
    original_attributes = reaction.attributes
    update_params = editing_params(reaction)

    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params.merge(reaction: { positive_count: "0", neutral_count: "0", negative_count: "0" })
    end

    assert_response :unprocessable_content
    assert_equal original_attributes, reaction.reload.attributes
    assert_editing_error(reaction, update_params[:displayed_reaction])
    assert_select "[role=alert] li", text: "リアクション人数を1人以上入力してください"
    assert_reaction_counts([ 0, 0, 0 ])

    corrected_params = update_params.merge(displayed_reaction: css_select("input[name=displayed_reaction]").first["value"])
    assert_no_difference "Reaction.count" do
      post reactions_url, params: corrected_params
    end
    assert_redirected_to reactions_url
    assert_equal [ 12, 3, 1 ], reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
  end

  test "ignores supplied reaction ids associations dates and timestamps when updating the loaded record" do
    reaction = saved_reaction
    other_reaction = saved_reaction(classroom: @classrooms.last)
    past_target = FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)
    past_reaction = saved_reaction(target: past_target)
    untouched_attributes = [ other_reaction, past_reaction ].map(&:attributes)
    original_id = reaction.id
    original_created_at = reaction.created_at
    update_params = editing_params(reaction)

    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params.merge(target_date: Date.yesterday, feedback_target_id: past_target.id,
        reaction: update_params[:reaction].merge(id: other_reaction.id, classroom_id: other_reaction.classroom_id,
          feedback_target_id: past_target.id, created_at: Time.utc(2000, 1, 1), updated_at: Time.utc(2000, 1, 1)))
    end

    assert_redirected_to reactions_url
    assert_equal [ 12, 3, 1 ], reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
    assert_equal original_id, reaction.id
    assert_equal original_created_at, reaction.created_at
    assert_equal @classrooms.first.id, reaction.classroom_id
    assert_equal @feedback_target.id, reaction.feedback_target_id
    assert_equal untouched_attributes, [ other_reaction, past_reaction ].map { |record| record.reload.attributes }
  end

  test "cannot use an editing token to update another class or kindergarten" do
    reaction = saved_reaction
    same_kindergarten_reaction = saved_reaction(classroom: @classrooms.last)
    other_classroom = Kindergarten.create!(name: "ひまわり幼稚園").classrooms.create!(name: "他園クラス")
    other_reaction = saved_reaction(classroom: other_classroom)
    original_attributes = Reaction.order(:id).map(&:attributes)
    update_params = editing_params(reaction)

    [ same_kindergarten_reaction.classroom_id, other_reaction.classroom_id ].each do |id|
      assert_no_difference "Reaction.count" do
        post reactions_url, params: update_params.merge(classroom_id: id)
      end

      assert_response :unprocessable_content
      assert_equal original_attributes, Reaction.order(:id).map(&:attributes)
    end
  end

  test "rejects invalid tampered and foreign record editing tokens" do
    reaction = saved_reaction
    other_reaction = saved_reaction(classroom: @classrooms.last)
    other_token = editing_params(other_reaction)[:displayed_reaction]
    update_params = editing_params(reaction)
    original_attributes = Reaction.order(:id).map(&:attributes)

    [ "invalid", "#{update_params[:displayed_reaction]}tampered", other_token, [ update_params[:displayed_reaction] ] ].each do |token|
      assert_no_difference "Reaction.count" do
        post reactions_url, params: update_params.merge(displayed_reaction: token)
      end

      assert_stale_entry("2026-10-08", "対象料理：カレー（主菜）")
      assert_equal original_attributes, Reaction.order(:id).map(&:attributes)
    end
  end

  test "rejects editing after midnight without changing either day's reaction" do
    reaction = saved_reaction
    tomorrow_target = FeedbackTarget.create!(dish: @dish, target_date: Date.tomorrow)
    saved_reaction(target: tomorrow_target)
    original_attributes = Reaction.order(:id).map(&:attributes)
    update_params = editing_params(reaction)
    travel_to Time.zone.local(2026, 10, 9, 0, 0)

    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params
    end
    assert_stale_entry("2026-10-09", "対象料理：カレー（主菜）")
    assert_equal original_attributes, Reaction.order(:id).map(&:attributes)
  end

  test "rejects editing a changed or replaced target and cannot reuse its editing token with a fresh target token" do
    reaction = saved_reaction
    update_params = editing_params(reaction)
    original_attributes = reaction.attributes
    @feedback_target.update!(dish: Dish.create!(name: "味噌汁", category: :soup))

    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params
    end
    assert_stale_entry("2026-10-08", "対象料理：味噌汁（汁物）")
    assert_equal original_attributes, reaction.reload.attributes

    @feedback_target.update!(target_date: Date.yesterday)
    @feedback_target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    replacement = saved_reaction
    original_attributes = replacement.attributes

    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params
    end
    assert_stale_entry("2026-10-08", "対象料理：カレー（主菜）")
    fresh_target_token = css_select("input[name=displayed_target]").first["value"]
    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params.merge(displayed_target: fresh_target_token)
    end
    assert_stale_entry("2026-10-08", "対象料理：カレー（主菜）")
    assert_equal original_attributes, replacement.reload.attributes
    assert_equal [ 2, 1, 0 ], reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
  end

  test "maintains save controls for loaded edits when logged out center role or today's target is unset" do
    reaction = saved_reaction
    original_attributes = reaction.attributes
    update_params = editing_params(reaction)
    delete kindergarten_logout_path

    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params
    end
    assert_redirected_to kindergarten_login_url
    assert_equal original_attributes, reaction.reload.attributes

    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "center-password" }
    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params
    end
    assert_response :forbidden
    assert_equal original_attributes, reaction.reload.attributes

    post kindergarten_login_path, params: { login_id: @user.login_id, password: "kindergarten-password" }
    @feedback_target.update!(target_date: Date.yesterday)
    assert_no_difference "Reaction.count" do
      post reactions_url, params: update_params
    end
    assert_response :unprocessable_content
    assert_select "[role=alert] li", text: "本日のフィードバック対象料理はまだ設定されていません。"
    assert_select "main form, main input", count: 0
    assert_equal original_attributes, reaction.reload.attributes
  end

  test "different classes and targets on other dates do not prevent a new reaction" do
    yesterday_target = FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)
    Reaction.create!(classroom: @classrooms.first, feedback_target: yesterday_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    Reaction.create!(classroom: @classrooms.last, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)

    assert_difference "Reaction.count", 1 do
      post reactions_url, params: registration_params
    end

    assert_redirected_to reactions_url
    assert Reaction.exists?(classroom: @classrooms.first, feedback_target: @feedback_target)
  end

  test "rejects stale forms after midnight in Japan and permits a new submission after review" do
    tomorrow_target = FeedbackTarget.create!(dish: Dish.create!(name: "味噌汁", category: :soup), target_date: Date.tomorrow)
    travel_to Time.zone.local(2026, 10, 9, 0, 0)

    assert_no_difference "Reaction.count" do
      post reactions_url, params: registration_params
    end

    assert_stale_entry("2026-10-09", "対象料理：味噌汁（汁物）")
    fresh_token = css_select("input[name=displayed_target]").first["value"]
    assert_difference "Reaction.count", 1 do
      post reactions_url, params: registration_params.merge(displayed_target: fresh_token)
    end
    assert_redirected_to reactions_url
    assert_equal tomorrow_target, Reaction.last.feedback_target
  end

  test "rejects a replaced target even when the dish is unchanged" do
    @feedback_target.destroy!
    @feedback_target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)

    assert_no_difference "Reaction.count" do
      post reactions_url, params: registration_params
    end

    assert_stale_entry("2026-10-08", "対象料理：カレー（主菜）")
  end

  test "rejects a changed dish on the same target record" do
    @feedback_target.update!(dish: Dish.create!(name: "味噌汁", category: :soup))

    assert_no_difference "Reaction.count" do
      post reactions_url, params: registration_params
    end

    assert_stale_entry("2026-10-08", "対象料理：味噌汁（汁物）")
  end

  test "rejects missing invalid and tampered display tokens" do
    [ nil, "invalid", "#{@displayed_target}tampered" ].each do |token|
      assert_no_difference "Reaction.count" do
        post reactions_url, params: registration_params.merge(displayed_target: token)
      end

      assert_stale_entry("2026-10-08", "対象料理：カレー（主菜）")
    end
  end

  test "shows registered guidance when a competing registration is caught by model validation" do
    assert_competing_registration(validate: true)
  end

  test "shows registered guidance after an actual database unique constraint conflict" do
    assert_competing_registration(validate: false)
  end

  test "results include all kindergartens and classes for today's target regardless of supplied filters" do
    Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    Reaction.create!(classroom: @classrooms.last, feedback_target: @feedback_target,
      positive_count: 1, neutral_count: 1, negative_count: 1)
    other_classroom = Kindergarten.create!(name: "ひまわり幼稚園").classrooms.create!(name: "年少")
    Reaction.create!(classroom: other_classroom, feedback_target: @feedback_target,
      positive_count: 1, neutral_count: 0, negative_count: 2)
    yesterday_target = FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)
    tomorrow_dish = Dish.create!(name: "味噌汁", category: :soup)
    tomorrow_target = FeedbackTarget.create!(dish: tomorrow_dish, target_date: Date.tomorrow)
    [ yesterday_target, tomorrow_target ].each do |target|
      Reaction.create!(classroom: @classrooms.first, feedback_target: target,
        positive_count: 99, neutral_count: 99, negative_count: 99)
    end

    [ {}, { classroom_id: @classrooms.first.id }, { classroom_id: other_classroom.id },
      { kindergarten_id: @kindergarten.id, target_date: Date.yesterday, feedback_target_id: yesterday_target.id },
      { target_date: Date.tomorrow, dish_id: tomorrow_dish.id } ].each do |filters|
      get reactions_url, params: filters

      assert_response :success
      assert_select "title", text: "本日の集計結果 | 給食リアクション"
      assert_select "h2", text: "本日の集計結果"
      assert_select "time[datetime='2026-10-08']", text: "2026年10月8日"
      assert_select ".reaction-results-dish", text: "対象料理：カレー"
      assert_results([ "4人 / 44.4%", "2人 / 22.2%", "3人 / 33.3%" ], 9)
      assert_select "main", text: /味噌汁/, count: 0
      assert_select "main input, main select, main form", count: 0
    end
  end

  test "results round percentages to one decimal and show zero and one hundred percent" do
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 1, neutral_count: 5, negative_count: 0)

    get reactions_url
    assert_results([ "1人 / 16.7%", "5人 / 83.3%", "0人 / 0.0%" ], 6)

    [ [ 1, 0, 0 ], [ 0, 1, 0 ], [ 0, 0, 1 ] ].each do |counts|
      reaction.update!(%i[ positive_count neutral_count negative_count ].zip(counts).to_h)
      get reactions_url
      assert_results(counts.map { |count| "#{count}人 / #{count == 1 ? '100.0%' : '0.0%'}" }, 1)
    end
  end

  test "results show zero people and dashes when today's target has no reactions" do
    get reactions_url

    assert_response :success
    assert_select ".reaction-results-dish", text: "対象料理：カレー"
    assert_results([ "0人 / -", "0人 / -", "0人 / -" ], 0)
    assert_select ".reaction-results-unset-notice", count: 0
  end

  test "results show the approved reload guidance and percentage note without the removed restriction note" do
    get reactions_url

    assert_select ".reaction-results-notes p", count: 2
    assert_select ".reaction-results-notes p:first-child", text: "※ 最新の集計を確認したい場合は、ページを再読み込みしてください。"
    assert_select ".reaction-results-notes p:last-child", text: "※ 3種類の割合の表示値を合計しても100.0%にならない場合がありますが、これは計算方法の不整合ではありません。"
    assert_select ".reaction-results-constraint", count: 0
    assert_select "main", text: /過去日閲覧はMVP対象外|ページを再読みしないと更新されません/, count: 0
  end

  test "results show today's date and unset guidance without totals or another day's dish" do
    @feedback_target.update!(target_date: Date.yesterday)
    saved_reaction

    get reactions_url, params: { target_date: Date.yesterday, feedback_target_id: @feedback_target.id }

    assert_response :success
    assert_select "h2", text: "本日の集計結果"
    assert_select "time[datetime='2026-10-08']", text: "2026年10月8日"
    assert_select ".reaction-results-unset-notice p", count: 2
    assert_select ".reaction-results-unset-notice p:first-child", text: "本日のフィードバック対象料理はまだ設定されていません。"
    assert_select ".reaction-results-unset-notice p:last-child", text: "給食センター側で設定されると、本日の集計結果を確認できるようになります。"
    assert_select ".reaction-results-dish, .reaction-results-count, .reaction-results-total, .reaction-results-notes", count: 0
    assert_select "main", text: /カレー/, count: 0
  end

  test "results use the current date across midnight in Japan" do
    yesterday_target = FeedbackTarget.create!(dish: Dish.create!(name: "味噌汁", category: :soup), target_date: Date.yesterday)
    Reaction.create!(classroom: @classrooms.first, feedback_target: yesterday_target,
      positive_count: 0, neutral_count: 1, negative_count: 0)

    travel_to Time.utc(2026, 10, 7, 14, 59, 59)
    get reactions_url
    assert_select "time[datetime='2026-10-07']", text: "2026年10月7日"
    assert_select ".reaction-results-dish", text: "対象料理：味噌汁"
    assert_results([ "0人 / 0.0%", "1人 / 100.0%", "0人 / 0.0%" ], 1)

    travel_to Time.utc(2026, 10, 7, 15, 0, 0)
    get reactions_url
    assert_select "time[datetime='2026-10-08']", text: "2026年10月8日"
    assert_select ".reaction-results-dish", text: "対象料理：カレー"
    assert_results([ "0人 / -", "0人 / -", "0人 / -" ], 0)
  end

  test "the kindergarten header links to results and results link back to entry" do
    get new_reaction_url
    assert_select "header a[href=?]", reactions_path, text: "集計結果", count: 1

    get reactions_url
    assert_select "header a[href=?]", new_reaction_path, text: "入力・編集", count: 1
  end

  test "results redirect logged out and deleted users and forbid center users" do
    @user.destroy!
    get reactions_url
    assert_redirected_to kindergarten_login_url
    assert_nil flash[:alert]

    delete kindergarten_logout_path
    get reactions_url
    assert_redirected_to kindergarten_login_url
    assert_nil flash[:alert]

    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "center-password" }
    get reactions_url
    assert_response :forbidden
    assert_empty response.body
    assert_nil flash[:alert]
  end

  test "viewing and reloading results never changes stored data and reflects later registrations and updates" do
    reaction = saved_reaction
    models = [ Reaction, FeedbackTarget, Dish, Classroom, Kindergarten, User ]
    original_data = models.map { |model| model.order(:id).map(&:attributes) }

    2.times do
      get reactions_url
      assert_results([ "2人 / 66.7%", "1人 / 33.3%", "0人 / 0.0%" ], 3)
    end
    assert_equal original_data, models.map { |model| model.order(:id).map(&:attributes) }

    reaction.update!(positive_count: 4)
    Reaction.create!(classroom: @classrooms.last, feedback_target: @feedback_target,
      positive_count: 0, neutral_count: 1, negative_count: 2)
    updated_data = models.map { |model| model.order(:id).map(&:attributes) }
    get reactions_url
    assert_results([ "4人 / 50.0%", "2人 / 25.0%", "2人 / 25.0%" ], 8)
    assert_equal updated_data, models.map { |model| model.order(:id).map(&:attributes) }
  end

  private

  def assert_results(values, total)
    labels = [ "美味しそうに食べていた", "普通・どちらでもない", "苦手そうに食べていた" ]
    assert_select ".reaction-results-count", count: 3
    assert_select ".reaction-results-count" do |rows|
      rows.zip(labels, values).each do |row, label, value|
        assert_select row, ".reaction-results-label", text: label, count: 1
        assert_select row, ".reaction-results-value", text: value, count: 1
      end
    end
    assert_select ".reaction-results-total", count: 1 do
      assert_select ".reaction-results-label", text: "観察対象人数：", count: 1
      assert_select ".reaction-results-value", text: "#{total}人", count: 1
    end
  end

  def saved_reaction(classroom: @classrooms.first, target: @feedback_target)
    Reaction.create!(classroom: classroom, feedback_target: target, positive_count: 2, neutral_count: 1, negative_count: 0)
  end

  def editing_params(reaction)
    get new_reaction_url, params: { classroom_id: reaction.classroom_id }
    registration_params.merge(classroom_id: reaction.classroom_id,
      displayed_target: css_select("input[name=displayed_target]").first["value"],
      displayed_reaction: css_select("input[name=displayed_reaction]").first["value"])
  end

  def assert_editing_error(reaction, token)
    assert_select "h2", text: "編集フォーム"
    assert_select "input[type=submit][value=更新]", count: 1
    assert_select "[role=alert] li", minimum: 1
    assert_select "select#classroom_id option[selected][value=?]", reaction.classroom_id
    assert_select ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{reaction.classroom.name}）", count: 1
    assert_select "input#loaded_classroom_id[value=?]", reaction.classroom_id
    assert_select "input[name=displayed_reaction][value=?]", token
  end

  def assert_reaction_counts(counts)
    %i[ positive_count neutral_count negative_count ].zip(counts).each do |attribute, count|
      assert_select "input#reaction_#{attribute}[value=?]", count.to_s, count: 1
    end
  end

  def registration_params
    { classroom_id: @classrooms.first.id, displayed_target: @displayed_target,
      reaction: { positive_count: "12", neutral_count: "3", negative_count: "1" } }
  end

  def assert_already_registered
    assert_response :unprocessable_content
    assert_select "[role=alert] li", text: "このクラスの本日のリアクションは登録済みです。"
    assert_select "main form[action=?][method=post]", reactions_path, count: 1
  end

  def assert_stale_entry(date, dish)
    assert_response :unprocessable_content
    assert_select "[role=alert] li", text: "対象日または対象料理が変更されています。最新の情報を確認し、再入力してください。"
    assert_select "time[datetime=?]", date
    assert_select ".reaction-entry-dish", text: dish
    assert_select "select#classroom_id option[selected]", count: 0
    assert_select ".reaction-entry-loaded-classroom", count: 0
    assert_select "main input[type=number][value='0']", count: 3
  end

  def assert_competing_registration(validate:)
    first_reaction = Reaction.new(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    second_reaction = Reaction.new(registration_params[:reaction])

    # 保存前の存在確認を通過した後に先行登録を保存する。
    # DB競合はsavepoint内で起こし、テスト全体のtransactionを保護する。
    second_reaction.define_singleton_method(:save) do
      first_reaction.save!
      Reaction.transaction(requires_new: true) { super(validate: validate) }
    end

    Reaction.define_singleton_method(:new) { |*| second_reaction }
    begin
      assert_difference "Reaction.count", 1 do
        post reactions_url, params: registration_params
      end
    ensure
      Reaction.singleton_class.remove_method(:new)
    end

    assert_already_registered
    assert first_reaction.persisted?
    assert_not second_reaction.persisted?
    assert_equal first_reaction, Reaction.find_by!(classroom: @classrooms.first, feedback_target: @feedback_target)
    assert_equal [ 2, 1, 0 ], first_reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
  end
end
