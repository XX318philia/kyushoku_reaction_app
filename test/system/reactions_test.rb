require "test_helper"

class ReactionsTest < ActionDispatch::SystemTestCase
  if ENV["SELENIUM_DRIVER_URL"].present?
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ],
      options: { browser: :remote, url: ENV.fetch("SELENIUM_DRIVER_URL") }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]
  end

  setup do
    if ENV["SELENIUM_DRIVER_URL"].present?
      Capybara.server_host = "0.0.0.0"
      Capybara.app_host = "http://web:#{Capybara.current_session.server.port}"
    end

    @kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    @user = User.create!(login_id: "ReactionSakura", password: "kindergarten-password",
      role: :kindergarten, kindergarten: @kindergarten)
    @classrooms = [ "年少", "年中" ].map { |name| @kindergarten.classrooms.create!(name: name) }
    dish = Dish.create!(name: "カレー", category: :main_dish)
    @feedback_target = FeedbackTarget.create!(dish: dish, target_date: Date.current)
  end

  test "login header navigation and changing inputs do not save or load existing reactions" do
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    original_attributes = reaction.attributes

    assert_no_difference "Reaction.count" do
      visit kindergarten_login_path
      fill_in "ログインID", with: @user.login_id
      fill_in "パスワード", with: "kindergarten-password"
      click_button "ログイン"

      assert_current_path new_reaction_path
      assert_noto_sans_jp_loaded
      assert_selector "main time", text: Date.current.strftime("%Y年%-m月%-d日")
      assert_selector "main", text: "対象料理：カレー（主菜）"
      assert_field "美味しそうに食べていた", with: "0"
      assert_field "普通・どちらでもない", with: "0"
      assert_field "苦手そうに食べていた", with: "0"
      assert_no_selector ".reaction-entry-loaded-classroom"

      [ 390, 1280 ].each do |width|
        page.driver.browser.manage.window.resize_to(width, 844)
        fill_in "美味しそうに食べていた", with: "12"
        fill_in "普通・どちらでもない", with: "3"
        fill_in "苦手そうに食べていた", with: "1"
        find_field("苦手そうに食べていた").send_keys(:arrow_up)
        assert_field "苦手そうに食べていた", with: "2"
        find_field("苦手そうに食べていた").send_keys(:arrow_down)
        assert_field "苦手そうに食べていた", with: "1"
        select "年少", from: "担当クラス"
        assert_select "担当クラス", selected: "年少"
        select "年中", from: "担当クラス"
        assert_select "担当クラス", selected: "年中"
        assert_no_selector ".reaction-entry-loaded-classroom"
        assert_field "美味しそうに食べていた", with: "12"
        assert_field "普通・どちらでもない", with: "3"
        assert_field "苦手そうに食べていた", with: "1"
        assert_current_path new_reaction_path
        assert_selector "main form[action='#{new_reaction_path}'][method=get]"
        assert_selector "main form[action='#{reactions_path}'][method=post]"
        assert_button "決定"
        assert_button "登録"
        assert page.evaluate_script(<<~JS), "Reaction entry overflows the viewport at #{width}px"
          document.documentElement.scrollWidth <= window.innerWidth &&
          [...document.querySelectorAll('main h2, main p, main select, main label, main input')].every(element => {
            const rect = element.getBoundingClientRect();
            return rect.left >= 0 && rect.right <= window.innerWidth;
          })
        JS
        assert_reaction_count_layout(width)
        assert_registration_layout(width)
        assert page.evaluate_script("Math.abs(document.querySelector('footer').getBoundingClientRect().bottom - window.innerHeight) <= 1")
        page.save_screenshot(Rails.root.join("tmp/screenshots/issue33-reactions-#{width}.png"))
      end

      visit root_path
      assert_no_selector "head link[href*='fonts.googleapis.com']", visible: :all
      click_link "入力・編集"
      assert_current_path new_reaction_path
      assert_noto_sans_jp_loaded
      assert_select "担当クラス", selected: "担当クラス"
      assert_no_selector ".reaction-entry-loaded-classroom"
      assert_field "美味しそうに食べていた", with: "0"
      assert_field "普通・どちらでもない", with: "0"
      assert_field "苦手そうに食べていた", with: "0"
    end

    assert_equal original_attributes, reaction.reload.attributes
  end

  test "long dish and class names fit mobile and desktop widths" do
    @feedback_target.dish.update!(name: "鶏肉とたっぷり野菜のやさしいクリーム煮", category: :fruit_or_dessert)
    @classrooms.first.update!(name: "ひまわり幼稚園の年少さんのさくらクラス")
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    original_id = reaction.id
    original_created_at = reaction.created_at
    visit kindergarten_login_path
    fill_in "ログインID", with: @user.login_id
    fill_in "パスワード", with: "kindergarten-password"
    click_button "ログイン"
    assert_noto_sans_jp_loaded

    [ 390, 1280 ].each do |width|
      page.driver.browser.manage.window.resize_to(width, 844)
      assert_selector ".reaction-entry-dish", text: "鶏肉とたっぷり野菜のやさしいクリーム煮（フルーツ・デザート）"
      select @classrooms.first.name, from: "担当クラス"
      click_button "決定"
      assert_select "担当クラス", selected: @classrooms.first.name
      assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）"
      assert_selector "main h2", text: "編集フォーム"
      assert_button "更新"
      assert_no_horizontal_overflow(width)
      assert page.evaluate_script(<<~JS), "The long registration class name does not wrap"
        (() => {
          const range = document.createRange();
          range.selectNodeContents(document.querySelector('.reaction-entry-loaded-classroom'));
          return range.getClientRects().length > 1;
        })()
      JS
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
      assert page.evaluate_script(<<~JS), "The class selector overlaps a wrapped dish name"
        document.querySelector('#classroom_id').getBoundingClientRect().top >=
          document.querySelector('.reaction-entry-dish').getBoundingClientRect().bottom + 12
      JS
      assert_reaction_count_layout(width)
      assert_registration_layout(width)
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue34-reactions-long-#{width}.png"))
      fill_in "美味しそうに食べていた", with: "12"
      fill_in "普通・どちらでもない", with: "3"
      fill_in "苦手そうに食べていた", with: "1"
      assert_no_difference "Reaction.count" do
        click_button "更新"
        assert_selector "[role=status]", text: "登録内容を更新しました"
      end
      assert_equal [ 12, 3, 1 ], reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
      assert_equal original_id, reaction.id
      assert_equal original_created_at, reaction.created_at
      assert_select "担当クラス", selected: "担当クラス"
      assert_no_horizontal_overflow(width)
    end
  end

  test "loads saved counts on decision and discards unsaved input when another class is loaded" do
    Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 0, neutral_count: 3, negative_count: 1)
    Reaction.create!(classroom: @classrooms.last, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 0, negative_count: 0)
    unregistered_classroom = @kindergarten.classrooms.create!(name: "年長")
    original_attributes = Reaction.order(:id).map(&:attributes)
    log_in

    assert_no_difference "Reaction.count" do
      [ 390, 1280 ].each do |width|
        page.driver.browser.manage.window.resize_to(width, 844)
        select @classrooms.first.name, from: "担当クラス"
        click_button "決定"
        assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）"
        assert_field "美味しそうに食べていた", with: "0"
        assert_field "普通・どちらでもない", with: "3"
        assert_field "苦手そうに食べていた", with: "1"
        assert_selector "main h2", text: "編集フォーム"
        assert_button "更新"
        assert_no_horizontal_overflow(width)
        assert_reaction_count_layout(width)
        assert_registration_layout(width)
        page.save_screenshot(Rails.root.join("tmp/screenshots/issue34-reactions-saved-#{width}.png"))

        select @classrooms.last.name, from: "担当クラス"
        assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）"
        assert_field "美味しそうに食べていた", with: "0"
        assert_field "普通・どちらでもない", with: "3"
        assert_field "苦手そうに食べていた", with: "1"
        assert_selector "input#loaded_classroom_id[value='#{@classrooms.first.id}']", visible: :all
        fill_in "美味しそうに食べていた", with: "12"
        click_button "決定"
        assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.last.name}）"
        assert_field "美味しそうに食べていた", with: "2"
        assert_field "普通・どちらでもない", with: "0"
        assert_field "苦手そうに食べていた", with: "0"
        assert_selector "main h2", text: "編集フォーム"
        assert_button "更新"

        fill_in "苦手そうに食べていた", with: "5"
        select unregistered_classroom.name, from: "担当クラス"
        click_button "決定"
        assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{unregistered_classroom.name}）"
        assert_field "美味しそうに食べていた", with: "0"
        assert_field "普通・どちらでもない", with: "0"
        assert_field "苦手そうに食べていた", with: "0"
        assert_selector "main h2", text: "入力フォーム"
        assert_button "登録"

        fill_in "普通・どちらでもない", with: "4"
        select "担当クラス", from: "担当クラス"
        click_button "決定"
        assert_select "担当クラス", selected: "担当クラス"
        assert_no_selector ".reaction-entry-loaded-classroom"
        assert_field "美味しそうに食べていた", with: "0"
        assert_field "普通・どちらでもない", with: "0"
        assert_field "苦手そうに食べていた", with: "0"
      end
    end

    assert_equal original_attributes, Reaction.order(:id).map(&:attributes)
  end

  test "registers only for the loaded class when another class is selected without a decision" do
    log_in

    [ 390, 1280 ].zip(@classrooms).each do |width, classroom|
      page.driver.browser.manage.window.resize_to(width, 844)
      select classroom.name, from: "担当クラス"
      click_button "決定"
      assert_select "担当クラス", selected: classroom.name
      assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{classroom.name}）"
      fill_in "美味しそうに食べていた", with: "4"
      select (@classrooms - [ classroom ]).first.name, from: "担当クラス"
      assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{classroom.name}）"

      assert_difference "Reaction.count", 1 do
        click_button "登録"
        assert_selector "[role=status]", text: "登録が成功しました"
      end

      reaction = Reaction.find_by!(classroom: classroom, feedback_target: @feedback_target)
      assert_equal [ 4, 0, 0 ], reaction.attributes.values_at("positive_count", "neutral_count", "negative_count")
      visit new_reaction_path
    end
  end

  test "selecting a class without loading it cannot register for that class" do
    log_in
    select @classrooms.first.name, from: "担当クラス"
    fill_in "美味しそうに食べていた", with: "4"

    assert_no_difference "Reaction.count" do
      click_button "登録"
      assert_selector "[role=alert]", text: "担当クラスを選択してください。"
    end

    assert_select "担当クラス", selected: "担当クラス"
    assert_no_selector ".reaction-entry-loaded-classroom"
    assert_field "美味しそうに食べていた", with: "4"
  end

  test "unset guidance wraps on mobile and desktop and refreshing after target setting restores the normal page" do
    @feedback_target.destroy!

    assert_no_difference "Reaction.count" do
      visit kindergarten_login_path
      fill_in "ログインID", with: @user.login_id
      fill_in "パスワード", with: "kindergarten-password"
      click_button "ログイン"

      assert_current_path new_reaction_path
      assert_noto_sans_jp_loaded
      assert_selector "main h2", text: "入力フォーム"
      assert_selector "main time", text: Date.current.strftime("%Y年%-m月%-d日")
      assert_selector ".reaction-entry-unset-notice p", count: 2
      assert_selector ".reaction-entry-unset-notice p:first-child", text: "本日のフィードバック対象料理はまだ設定されていません。"
      assert_selector ".reaction-entry-unset-notice p:last-child", text: "給食センター側で設定されると、リアクションを入力できるようになります。"
      assert_no_selector ".reaction-entry-dish, main label, main select, main input, main button, main form"

      [ 390, 1280 ].each do |width|
        page.driver.browser.manage.window.resize_to(width, 844)
        assert page.evaluate_script(<<~JS), "Unset guidance overflows or does not wrap at #{width}px"
          document.documentElement.scrollWidth <= window.innerWidth &&
          [...document.querySelectorAll('.reaction-entry-unset-notice p')].every(element => {
            const rect = element.getBoundingClientRect();
            const range = document.createRange();
            range.selectNodeContents(element);
            return rect.left >= 0 && rect.right <= window.innerWidth &&
              element.scrollWidth <= element.clientWidth && range.getClientRects().length > 1;
          })
        JS
        assert page.evaluate_script(<<~JS), "Unset guidance changes the content width, alignment or text styling at #{width}px"
          (() => {
            const content = document.querySelector('.reaction-entry-content');
            const rect = content.getBoundingClientRect();
            const notice = document.querySelector('.reaction-entry-unset-notice');
            const elements = [notice, ...notice.querySelectorAll('p')];
            return Math.abs(rect.width - 326) <= 1 &&
              Math.abs((rect.left + rect.right) / 2 - document.documentElement.clientWidth / 2) <= 1 &&
              getComputedStyle(document.querySelector('.reaction-entry-date')).fontSize === '16px' &&
              elements.every(element => {
                const style = getComputedStyle(element);
                return style.color === 'rgb(0, 0, 0)' && style.fontSize === '15px' &&
                  style.fontWeight === '400' && style.textDecorationLine === 'none' &&
                  ['Top', 'Right', 'Bottom', 'Left'].every(side => style['border' + side + 'Width'] === '0px');
              });
          })()
        JS
        page.save_screenshot(Rails.root.join("tmp/screenshots/issue30-reactions-unset-#{width}.png"))
      end

      FeedbackTarget.create!(dish: @feedback_target.dish, target_date: Date.current)
      page.refresh

      assert_current_path new_reaction_path
      assert_no_selector ".reaction-entry-unset-notice"
      assert_selector ".reaction-entry-dish", text: "対象料理：カレー（主菜）"
      assert_select "担当クラス", selected: "担当クラス"
      assert_selector "main input[type=number][value='0']", count: 3
      assert_selector "main form[action='#{reactions_path}'][method=post]"
      assert_button "登録"
    end
  end

  test "registers from mobile and desktop and returns to the input page with a success message" do
    log_in

    [ 390, 1280 ].zip(@classrooms).each do |width, classroom|
      page.driver.browser.manage.window.resize_to(width, 844)
      select classroom.name, from: "担当クラス"
      click_button "決定"
      assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{classroom.name}）"
      fill_in "美味しそうに食べていた", with: "12"
      fill_in "普通・どちらでもない", with: "3"
      fill_in "苦手そうに食べていた", with: "1"

      assert_difference "Reaction.count", 1 do
        click_button "登録"
        assert_current_path new_reaction_path
        assert_selector ".alert.alert-success[role=status]", text: "登録が成功しました"
      end

      reaction = Reaction.find_by!(classroom: classroom, feedback_target: @feedback_target)
      assert_equal [ 12, 3, 1 ], reaction.attributes.values_at("positive_count", "neutral_count", "negative_count")
      assert_select "担当クラス", selected: "担当クラス"
      assert_field "美味しそうに食べていた", with: "0"
      assert_no_selector "[role=alert]"
      assert_no_horizontal_overflow(width)
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue32-reactions-success-#{width}.png"))

      visit new_reaction_path
      assert_no_selector "[role=status]"
    end
  end

  test "all zero submission shows errors preserves inputs and can be corrected on mobile and desktop" do
    log_in

    [ 390, 1280 ].zip(@classrooms).each do |width, classroom|
      page.driver.browser.manage.window.resize_to(width, 844)
      select classroom.name, from: "担当クラス"
      click_button "決定"
      assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{classroom.name}）"
      select (@classrooms - [ classroom ]).first.name, from: "担当クラス"

      assert_no_difference "Reaction.count" do
        click_button "登録"
        assert_selector ".alert.alert-danger[role=alert]", text: "リアクション人数を1人以上入力してください"
      end

      assert_select "担当クラス", selected: classroom.name
      assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{classroom.name}）"
      assert_field "美味しそうに食べていた", with: "0"
      assert_field "普通・どちらでもない", with: "0"
      assert_field "苦手そうに食べていた", with: "0"
      assert_no_horizontal_overflow(width)
      assert_reaction_count_layout(width)
      assert_registration_layout(width)
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue32-reactions-error-#{width}.png"))

      fill_in "美味しそうに食べていた", with: "2"
      assert_difference "Reaction.count", 1 do
        click_button "登録"
        assert_selector "[role=status]", text: "登録が成功しました"
      end
      visit new_reaction_path
    end
  end

  test "updates only the loaded class from mobile and desktop and resets the class selection" do
    reactions = @classrooms.map do |classroom|
      Reaction.create!(classroom: classroom, feedback_target: @feedback_target,
        positive_count: 2, neutral_count: 1, negative_count: 0)
    end
    log_in

    [ 390, 1280 ].zip(reactions).each do |width, reaction|
      page.driver.browser.manage.window.resize_to(width, 844)
      select reaction.classroom.name, from: "担当クラス"
      click_button "決定"
      assert_selector "main h2", text: "編集フォーム"
      assert_button "更新"
      assert_no_button "登録"
      assert_field "美味しそうに食べていた", with: "2"
      assert_field "普通・どちらでもない", with: "1"
      assert_field "苦手そうに食べていた", with: "0"
      assert_reaction_count_layout(width)
      assert_registration_layout(width)
      original_id = reaction.id
      original_created_at = reaction.created_at
      other_reaction = (reactions - [ reaction ]).first
      other_attributes = other_reaction.reload.attributes

      fill_in "美味しそうに食べていた", with: "12"
      fill_in "普通・どちらでもない", with: "3"
      fill_in "苦手そうに食べていた", with: "1"
      select other_reaction.classroom.name, from: "担当クラス"
      assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{reaction.classroom.name}）"
      assert_no_difference "Reaction.count" do
        click_button "更新"
        assert_current_path new_reaction_path
        assert_selector "[role=status]", text: "登録内容を更新しました"
      end

      assert_equal [ 12, 3, 1 ], reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
      assert_equal original_id, reaction.id
      assert_equal original_created_at, reaction.created_at
      assert_equal other_attributes, other_reaction.reload.attributes
      assert_select "担当クラス", selected: "担当クラス"
      assert_no_selector ".reaction-entry-loaded-classroom"
      assert_selector "main h2", text: "入力フォーム"
      assert_button "登録"
      assert_field "美味しそうに食べていた", with: "0"
      assert_field "普通・どちらでもない", with: "0"
      assert_field "苦手そうに食べていた", with: "0"
      assert_no_horizontal_overflow(width)
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue34-reactions-success-#{width}.png"))
      visit new_reaction_path
      assert_no_selector "[role=status]"
    end
  end

  test "failed edits preserve the loaded class and inputs and can be corrected on mobile and desktop" do
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    log_in

    [ 390, 1280 ].each do |width|
      page.driver.browser.manage.window.resize_to(width, 844)
      select reaction.classroom.name, from: "担当クラス"
      click_button "決定"
      original_attributes = reaction.reload.attributes
      [ "0", "-1" ].each do |positive_count|
        fill_in "美味しそうに食べていた", with: positive_count
        fill_in "普通・どちらでもない", with: "0"
        fill_in "苦手そうに食べていた", with: "0"
        # 負数の送信もサーバー側で拒否し、編集状態が保持されることを確認する。
        page.execute_script("document.querySelector('main form[method=post]').noValidate = true")

        assert_no_difference "Reaction.count" do
          click_button "更新"
          message = positive_count == "0" ? "リアクション人数を1人以上入力してください" : "Positive count must be greater than or equal to 0"
          assert_selector "[role=alert]", text: message
        end
        assert_equal original_attributes, reaction.reload.attributes
        assert_select "担当クラス", selected: reaction.classroom.name
        assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{reaction.classroom.name}）"
        assert_selector "main h2", text: "編集フォーム"
        assert_button "更新"
        assert_field "美味しそうに食べていた", with: positive_count
        assert_field "普通・どちらでもない", with: "0"
        assert_field "苦手そうに食べていた", with: "0"
        assert_no_horizontal_overflow(width)
        assert_reaction_count_layout(width)
        assert_registration_layout(width)
      end
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue34-reactions-error-#{width}.png"))

      fill_in "美味しそうに食べていた", with: "8"
      assert_no_difference "Reaction.count" do
        click_button "更新"
        assert_selector "[role=status]", text: "登録内容を更新しました"
      end
      assert_equal [ 8, 0, 0 ], reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
      visit new_reaction_path
    end
  end

  test "an initial registration form cannot overwrite a competing registration" do
    log_in
    select @classrooms.first.name, from: "担当クラス"
    click_button "決定"
    assert_selector "main h2", text: "入力フォーム"
    fill_in "美味しそうに食べていた", with: "12"
    fill_in "普通・どちらでもない", with: "3"
    fill_in "苦手そうに食べていた", with: "1"
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    original_attributes = reaction.attributes

    assert_no_difference "Reaction.count" do
      click_button "登録"
      assert_selector "[role=alert]", text: "このクラスの本日のリアクションは登録済みです。"
    end
    assert_equal original_attributes, reaction.reload.attributes
    assert_field "美味しそうに食べていた", with: "12"
    assert_field "普通・どちらでもない", with: "3"
    assert_field "苦手そうに食べていた", with: "1"
    assert_select "担当クラス", selected: @classrooms.first.name
    assert_selector "main h2", text: "入力フォーム"
    assert_button "登録"

    click_button "決定"
    assert_selector "main h2", text: "編集フォーム"
    assert_button "更新"
    assert_field "美味しそうに食べていた", with: "2"
  end

  test "a registered class can be edited again after a successful update" do
    reaction = Reaction.create!(classroom: @classrooms.first, feedback_target: @feedback_target,
      positive_count: 2, neutral_count: 1, negative_count: 0)
    original_attributes = reaction.attributes
    log_in
    select @classrooms.first.name, from: "担当クラス"
    click_button "決定"
    assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）"
    fill_in "美味しそうに食べていた", with: "12"

    assert_no_difference "Reaction.count" do
      click_button "更新"
      assert_selector "[role=status]", text: "登録内容を更新しました"
    end

    assert_equal [ 12, 1, 0 ], reaction.reload.attributes.values_at("positive_count", "neutral_count", "negative_count")
    assert_equal original_attributes["id"], reaction.id
    assert_equal original_attributes["created_at"], reaction.created_at
    select @classrooms.first.name, from: "担当クラス"
    click_button "決定"
    assert_field "美味しそうに食べていた", with: "12"
    assert_field "普通・どちらでもない", with: "1"
    assert_field "苦手そうに食べていた", with: "0"
    assert_select "担当クラス", selected: @classrooms.first.name
    assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）"
    assert_selector "main h2", text: "編集フォーム"
    assert_button "更新"
    assert_no_selector "[role=status]"
  end

  test "decimal input rejected by the server retains the entered counts on mobile and desktop" do
    log_in
    select @classrooms.first.name, from: "担当クラス"
    click_button "決定"
    assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）"
    fill_in "美味しそうに食べていた", with: "1.5"
    fill_in "普通・どちらでもない", with: "3"
    fill_in "苦手そうに食べていた", with: "1"

    # ブラウザのstep検証を省略し、サーバーのバリデーションと再表示を確認する。
    page.execute_script("document.querySelector('main form[method=post]').noValidate = true")
    assert_no_difference "Reaction.count" do
      click_button "登録"
      assert_selector ".alert.alert-danger[role=alert]", text: "Positive count must be an integer"
    end

    [ 390, 1280 ].each do |width|
      page.driver.browser.manage.window.resize_to(width, 844)
      assert_select "担当クラス", selected: @classrooms.first.name
      assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）"
      assert_field "美味しそうに食べていた", with: "1.5"
      assert_field "普通・どちらでもない", with: "3"
      assert_field "苦手そうに食べていた", with: "1"
      assert_no_horizontal_overflow(width)
      assert_reaction_count_layout(width)
      assert_registration_layout(width)
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue32-reactions-count-error-#{width}.png"))
    end
  end

  test "a stale form shows the latest dish and requires new input before registration" do
    log_in
    select @classrooms.first.name, from: "担当クラス"
    click_button "決定"
    assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）"
    fill_in "美味しそうに食べていた", with: "12"
    @feedback_target.update!(dish: Dish.create!(name: "味噌汁", category: :soup))

    assert_no_difference "Reaction.count" do
      click_button "登録"
      assert_selector "[role=alert]", text: "対象日または対象料理が変更されています。最新の情報を確認し、再入力してください。"
    end

    assert_selector ".reaction-entry-dish", text: "対象料理：味噌汁（汁物）"
    assert_select "担当クラス", selected: "担当クラス"
    assert_no_selector ".reaction-entry-loaded-classroom"
    assert_field "美味しそうに食べていた", with: "0"
    assert_field "普通・どちらでもない", with: "0"
    assert_field "苦手そうに食べていた", with: "0"
    assert_no_horizontal_overflow(390)
    page.save_screenshot(Rails.root.join("tmp/screenshots/issue32-reactions-stale-390.png"))

    select @classrooms.first.name, from: "担当クラス"
    click_button "決定"
    assert_selector ".reaction-entry-loaded-classroom", text: "（登録対象クラス：#{@classrooms.first.name}）"
    fill_in "普通・どちらでもない", with: "2"
    assert_difference "Reaction.count", 1 do
      click_button "登録"
      assert_selector "[role=status]", text: "登録が成功しました"
    end
    assert_equal @feedback_target, Reaction.last.feedback_target
  end

  private

  def log_in
    visit kindergarten_login_path
    fill_in "ログインID", with: @user.login_id
    fill_in "パスワード", with: "kindergarten-password"
    click_button "ログイン"
    assert_current_path new_reaction_path
  end

  def assert_no_horizontal_overflow(width)
    overflows = page.evaluate_script(<<~JS)
      (() => {
        const overflows = [...document.querySelectorAll('main .alert, main form, main select, main input[type=number], main input[type=submit], .reaction-entry-loaded-classroom')].flatMap(element => {
          const rect = element.getBoundingClientRect();
          // ネイティブselectは長い選択肢を枠内で省略表示するため、描画枠の位置で検証する。
          const contentFits = element.tagName === 'SELECT' || element.scrollWidth <= element.clientWidth;
          return rect.left >= 0 && rect.right <= window.innerWidth && contentFits ? [] :
            [{ element: element.id || element.className, left: rect.left, right: rect.right,
               scrollWidth: element.scrollWidth, clientWidth: element.clientWidth }];
        });
        if (document.documentElement.scrollWidth > window.innerWidth) overflows.push({ element: 'document' });
        return overflows;
      })()
    JS
    assert_empty overflows, "Reaction entry overflows at #{width}px"
  end

  def assert_registration_layout(width)
    assert_selector ".reaction-entry-constraint", text: "入力制約：0以上の整数"
    assert page.evaluate_script(<<~JS), "Registration button or constraint text differs from Figma at #{width}px"
      (() => {
        const constraint = document.querySelector('.reaction-entry-constraint');
        const constraintStyle = getComputedStyle(constraint);
        const constraintRect = constraint.getBoundingClientRect();
        const lastInput = document.querySelector('#reaction_negative_count').getBoundingClientRect();
        const button = document.querySelector('.reaction-entry-submit');
        const style = getComputedStyle(button);
        const rect = button.getBoundingClientRect();
        return Math.abs(rect.width - 326) <= 1 && Math.abs(rect.height - 42) <= 1 &&
          Math.abs((rect.left + rect.right) / 2 - document.documentElement.clientWidth / 2) <= 1 &&
          Math.abs(constraintRect.top - lastInput.bottom - 14) <= 1 &&
          Math.abs(rect.top - constraintRect.bottom - 40) <= 1 &&
          constraintStyle.fontSize === '10px' && constraintStyle.fontWeight === '400' &&
          constraintStyle.color === 'rgb(31, 31, 31)' && constraintStyle.fontFamily.includes('Noto Sans JP') &&
          style.backgroundColor === 'rgb(237, 237, 237)' && style.color === 'rgb(31, 31, 31)' &&
          style.fontSize === '13px' && style.fontWeight === '400' &&
          style.fontFamily.includes('Noto Sans JP') && style.textDecorationLine === 'none' &&
          ['Top', 'Right', 'Bottom', 'Left'].every(side =>
            style['border' + side + 'Width'] === '1px' && style['border' + side + 'Style'] === 'solid' &&
            style['border' + side + 'Color'] === 'rgb(31, 31, 31)') &&
          ['TopLeft', 'TopRight', 'BottomLeft', 'BottomRight'].every(corner => style['border' + corner + 'Radius'] === '0px');
      })()
    JS
  end

  def assert_noto_sans_jp_loaded
    assert_selector "head link[href*='fonts.googleapis.com']", visible: :all, wait: 10 do
      page.evaluate_script("[...document.fonts].some(font => font.family.includes('Noto Sans JP'))")
    end
    assert page.evaluate_async_script(<<~JS), "Noto Sans JP did not load for the reaction page"
      const done = arguments[arguments.length - 1];
      document.fonts.load('400 11px "Noto Sans JP"', '美味しそうに食べていた').then(fonts => {
        document.fonts.ready.then(() => done(fonts.length > 0 && fonts.every(font => font.status === 'loaded')));
      }).catch(() => done(false));
    JS
  end

  def assert_reaction_count_layout(width)
    assert page.evaluate_script(<<~JS), "Class selector and decision button differ from Figma at #{width}px"
      (() => {
        const select = document.querySelector('#classroom_id');
        const selectRect = select.getBoundingClientRect();
        const selectStyle = getComputedStyle(select);
        const button = document.querySelector('.reaction-entry-load');
        const rect = button.getBoundingClientRect();
        const style = getComputedStyle(button);
        return Math.abs(selectRect.width - 181) <= 1 && Math.abs(selectRect.height - 40) <= 1 &&
          selectStyle.fontSize === '11px' &&
          Math.abs(rect.width - 135) <= 1 && Math.abs(rect.height - 40) <= 1 &&
          Math.abs(rect.left - selectRect.right - 10) <= 1 && Math.abs(rect.top - selectRect.top) <= 1 &&
          style.backgroundColor === 'rgb(237, 237, 237)' && style.color === 'rgb(31, 31, 31)' &&
          style.fontSize === '13px' && style.fontWeight === '400' &&
          style.fontFamily.includes('Noto Sans JP') && style.textDecorationLine === 'none' &&
          ['Top', 'Right', 'Bottom', 'Left'].every(side =>
            style['border' + side + 'Width'] === '1px' && style['border' + side + 'Style'] === 'solid' &&
            style['border' + side + 'Color'] === 'rgb(31, 31, 31)') &&
          ['TopLeft', 'TopRight', 'BottomLeft', 'BottomRight'].every(corner => style['border' + corner + 'Radius'] === '0px');
      })()
    JS
    assert page.evaluate_script(<<~JS), "Reaction count inputs differ from the design or overlap at #{width}px"
      (() => {
        let previousRect = document.querySelector('#classroom_id').getBoundingClientRect();
        let firstGap = 12;
        const loadedClassroom = document.querySelector('.reaction-entry-loaded-classroom');
        if (loadedClassroom) {
          const rect = loadedClassroom.getBoundingClientRect();
          const style = getComputedStyle(loadedClassroom);
          if (Math.abs(rect.top - previousRect.bottom - 30) > 1 ||
              style.fontSize !== '16px' || style.fontWeight !== '400' || style.lineHeight !== '20px' ||
              style.color !== 'rgb(31, 31, 31)' || style.textDecorationLine !== 'none' ||
              !style.fontFamily.includes('Noto Sans JP')) return false;
          previousRect = rect;
          firstGap = 6;
        }
        if (getComputedStyle(document.querySelector('main h2')).fontSize !== '22px' ||
            getComputedStyle(document.querySelector('.reaction-entry-date')).fontSize !== '16px' ||
            getComputedStyle(document.querySelector('.reaction-entry-dish')).fontSize !== '16px') return false;
        return [...document.querySelectorAll('.reaction-entry-count')].every(field => {
          const input = field.querySelector('input');
          const label = field.querySelector('label');
          const rect = input.getBoundingClientRect();
          const labelRect = label.getBoundingClientRect();
          const style = getComputedStyle(input);
          const labelStyle = getComputedStyle(label);
          const matches = Math.abs(rect.width - 326) <= 1 && Math.abs(rect.height - 40) <= 1 &&
            Math.abs((rect.left + rect.right) / 2 - document.documentElement.clientWidth / 2) <= 1 &&
            Math.abs(rect.top - previousRect.bottom - firstGap) <= 1 &&
            rect.left >= 0 && rect.right <= window.innerWidth &&
            labelRect.left >= rect.left && labelRect.right <= rect.left + parseFloat(style.paddingLeft) &&
            labelRect.top >= rect.top && labelRect.bottom <= rect.bottom &&
            style.backgroundColor === 'rgb(255, 255, 255)' && style.color === 'rgb(31, 31, 31)' &&
            style.fontFamily.includes('Noto Sans JP') && style.fontSize === '14px' &&
            style.fontWeight === '400' && style.textDecorationLine === 'none' &&
            labelStyle.color === style.color && labelStyle.fontSize === '11px' &&
            labelStyle.fontWeight === '400' && labelStyle.textDecorationLine === 'none' &&
            ['Top', 'Right', 'Bottom', 'Left'].every(side =>
              style['border' + side + 'Width'] === '1px' &&
              style['border' + side + 'Style'] === 'solid' &&
              style['border' + side + 'Color'] === 'rgb(31, 31, 31)') &&
            ['TopLeft', 'TopRight', 'BottomLeft', 'BottomRight'].every(corner =>
              style['border' + corner + 'Radius'] === '0px');
          previousRect = rect;
          firstGap = 12;
          return matches;
        });
      })()
    JS
  end
end
