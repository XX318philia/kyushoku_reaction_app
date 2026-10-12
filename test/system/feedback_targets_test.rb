require "test_helper"

class FeedbackTargetsTest < ActionDispatch::SystemTestCase
  if ENV["SELENIUM_DRIVER_URL"].present?
    driven_by :selenium, using: :headless_chrome, screen_size: [ 960, 720 ],
      options: { browser: :remote, url: ENV.fetch("SELENIUM_DRIVER_URL") }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 960, 720 ]
  end

  setup do
    if ENV["SELENIUM_DRIVER_URL"].present?
      Capybara.server_host = "0.0.0.0"
      Capybara.app_host = "http://web:#{Capybara.current_session.server.port}"
    end

    @user = User.create!(login_id: "CenterCancel", password: "center-password", role: :center)
    @dish = Dish.create!(name: "カレー", category: :main_dish)
  end

  test "confirmation and cancel retain a zero reaction target then deletion shows notice and permits resetting" do
    log_in
    visit new_feedback_target_path
    assert_no_link "本日の設定を取り消す"
    select "カレー（主菜）", from: "対象料理"
    click_button "設定"
    assert_current_path center_reaction_results_path
    target = FeedbackTarget.find_by!(target_date: Date.current)
    click_link "対象料理設定"

    assert_no_difference [ "FeedbackTarget.count", "Reaction.count" ] do
      click_link "本日の設定を取り消す"
      assert_current_path confirm_destroy_feedback_target_path(target)
      assert_selector "main time", text: Date.current.strftime("%Y年%-m月%-d日")
      assert_text "対象料理：カレー（主菜）"
      assert_text "本日の対象料理とリアクション記録が削除されます。"
      assert_text "この操作は元に戻せません。"
      assert_no_text "仕様について"
      assert_no_text "flash"
      click_link "キャンセル"
      assert_current_path new_feedback_target_path
      assert_selector ".feedback-target-setting--configured"
    end

    click_link "本日の設定を取り消す"
    click_button "本日の設定を取り消す"
    assert_current_path new_feedback_target_path
    assert_selector "h2 + [role=status]", exact_text: "本日の対象料理を取り消しました"
    assert_no_link "本日の設定を取り消す"
    assert_no_selector ".feedback-target-setting--configured"
    assert_not FeedbackTarget.exists?(target.id)
    select "カレー（主菜）", from: "対象料理"
    click_button "設定"
    assert_current_path center_reaction_results_path
    assert_selector ".center-reaction-results-dish", text: "カレー"
    assert_not_equal target.id, FeedbackTarget.find_by!(target_date: Date.current).id
  end

  test "cancellation after registration preserves history and shows unset state on results and kindergarten refresh" do
    kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    user = User.create!(login_id: "SakuraCancel", password: "kindergarten-password", role: :kindergarten, kindergarten: kindergarten)
    classrooms = [ "年少", "年中" ].map { |name| kindergarten.classrooms.create!(name: name) }
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    classrooms.each do |classroom|
      Reaction.create!(classroom: classroom, feedback_target: target, positive_count: 2, neutral_count: 1, negative_count: 0)
    end
    past_target = FeedbackTarget.create!(dish: @dish, target_date: Date.yesterday)
    past_reaction = Reaction.create!(classroom: classrooms.first, feedback_target: past_target,
      positive_count: 1, neutral_count: 0, negative_count: 0)
    retained_data = [ Dish, User, Kindergarten, Classroom ].map { |model| model.order(:id).map(&:attributes) }

    log_in
    click_link "対象料理設定"
    click_link "本日の設定を取り消す"
    click_button "本日の設定を取り消す"
    assert_selector "[role=status]", text: "本日の対象料理を取り消しました"
    click_link "当日集計結果"
    assert_current_path center_reaction_results_path
    page.refresh
    assert_selector ".center-reaction-results-unset-notice"
    assert_no_selector ".center-reaction-results-grid"
    assert_equal [ past_target.id ], FeedbackTarget.pluck(:id)
    assert_equal [ past_reaction.id ], Reaction.pluck(:id)
    assert_equal retained_data, [ Dish, User, Kindergarten, Classroom ].map { |model| model.order(:id).map(&:attributes) }

    log_in_kindergarten(user)
    page.refresh
    assert_selector ".reaction-entry-unset-notice"
    assert_no_selector "main form"
    assert_no_button "更新"
  end

  test "refreshing a kindergarten edit screen after cancellation shows the unset state" do
    kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    user = User.create!(login_id: "SakuraRefresh", password: "kindergarten-password", role: :kindergarten, kindergarten: kindergarten)
    classroom = kindergarten.classrooms.create!(name: "年少")
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    Reaction.create!(classroom: classroom, feedback_target: target, positive_count: 2, neutral_count: 1, negative_count: 0)
    log_in_kindergarten(user)
    select classroom.name, from: "担当クラス"
    click_button "決定"
    assert_selector "h2", text: "編集フォーム"
    assert_button "更新"

    target.destroy!
    page.refresh

    assert_selector ".reaction-entry-unset-notice"
    assert_no_selector "main form"
    assert_no_button "更新"
  end

  test "old confirmations display the current configured or unset state without deleting replacement data" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    log_in
    visit confirm_destroy_feedback_target_path(target)
    other_dish = Dish.create!(name: "味噌汁", category: :soup)
    target.update!(dish: other_dish)
    click_button "本日の設定を取り消す"
    assert_current_path new_feedback_target_path
    assert_selector "h2 + [role=alert]", text: "設定が変更されたため"
    assert_text "対象料理：味噌汁（汁物）"
    assert FeedbackTarget.exists?(target.id)

    click_link "本日の設定を取り消す"
    assert_current_path confirm_destroy_feedback_target_path(target)
    assert_button "本日の設定を取り消す"
    target.destroy!
    click_button "本日の設定を取り消す"
    assert_current_path new_feedback_target_path
    assert_selector "h2 + [role=alert]", text: "設定が変更されたため"
    assert_select "対象料理"
    assert_no_link "本日の設定を取り消す"
  end

  test "configured and confirmation screens match Figma and keep buttons side by side on narrow screens" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    log_in
    [ 320, 390, 767, 768, 960, 1280 ].each do |width|
      resize_viewport(width)
      visit new_feedback_target_path
      assert_selector ".feedback-target-setting--configured"
      assert_font_loaded
      assert_fits_viewport(width)
      assert_configured_design
      assert_configured_positions if width == 960
      save_screen("configured", width)
      click_link "本日の設定を取り消す"
      assert_current_path confirm_destroy_feedback_target_path(target)
      assert_font_loaded
      assert_fits_viewport(width)
      assert_confirmation_design
      assert_confirmation_positions if width == 960
      save_screen("confirmation", width)
    end

    @dish.update!(name: "鶏肉とたっぷり野菜のやさしいクリーム煮" * 3)
    [ 320, 390, 960 ].each do |width|
      resize_viewport(width)
      visit new_feedback_target_path
      assert_fits_viewport(width)
      click_link "本日の設定を取り消す"
      assert_current_path confirm_destroy_feedback_target_path(target)
      assert_fits_viewport(width)
      assert_confirmation_design
    end
  end

  private

  def log_in
    visit center_login_path
    fill_in "ログインID", with: @user.login_id
    fill_in "パスワード", with: "center-password"
    click_button "ログイン"
    assert_current_path center_reaction_results_path
  end

  def log_in_kindergarten(user)
    visit kindergarten_login_path
    fill_in "ログインID", with: user.login_id
    fill_in "パスワード", with: "kindergarten-password"
    click_button "ログイン"
    assert_current_path new_reaction_path
  end

  def resize_viewport(width)
    height = width == 960 ? 720 : 844
    browser = page.driver.browser
    browser.manage.window.resize_to(width, height)
    chrome_height = height - page.evaluate_script("window.innerHeight")
    browser.manage.window.resize_to(width, height + chrome_height)
    assert_equal width, page.evaluate_script("window.innerWidth")
  end

  def assert_font_loaded
    assert page.evaluate_async_script(<<~JS), "Noto Sans JP did not load"
      const done = arguments[arguments.length - 1];
      document.fonts.load('400 20px "Noto Sans JP"', '本日の設定を取り消す').then(fonts => {
        document.fonts.ready.then(() => done(fonts.length > 0 && fonts.every(font => font.status === 'loaded')));
      }).catch(() => done(false));
    JS
  end

  def assert_fits_viewport(width)
    assert page.evaluate_script(<<~JS), "Cancellation UI overflows at #{width}px"
      document.documentElement.scrollWidth <= window.innerWidth &&
        [...document.querySelectorAll('main h2, main p, main a, main button')].every(element => {
          const rect = element.getBoundingClientRect();
          return rect.left >= 0 && rect.right <= window.innerWidth + 1 &&
            element.scrollWidth <= element.clientWidth + 1;
        })
    JS
  end

  def assert_configured_design
    assert page.evaluate_script(<<~JS), "Configured target differs from Figma"
      (() => {
        const main = document.querySelector('main');
        const style = getComputedStyle(main);
        const heading = getComputedStyle(main.querySelector('h2'));
        const date = getComputedStyle(main.querySelector('.feedback-target-setting-date'));
        const button = main.querySelector('.feedback-target-cancel-link');
        return style.backgroundColor === 'rgb(255, 255, 255)' && style.color === 'rgb(31, 31, 31)' &&
          style.fontFamily.includes('Noto Sans JP') && heading.fontSize === '28px' &&
          heading.fontWeight === '400' && heading.color === 'rgb(0, 0, 0)' && date.fontSize === '20px' &&
          [...main.querySelectorAll('.feedback-target-setting-state p')].every(element => {
            const text = getComputedStyle(element);
            return text.fontSize === '20px' && text.fontWeight === '400' &&
              text.color === 'rgb(0, 0, 0)' && text.textDecorationLine === 'none';
          }) && #{button_style_check} && Math.abs(button.getBoundingClientRect().height - 48) <= 1;
      })()
    JS
  end

  def assert_confirmation_design
    assert page.evaluate_script(<<~JS), "Confirmation buttons differ from Figma or do not stay side by side"
      (() => {
        const main = document.querySelector('main');
        const style = getComputedStyle(main);
        const buttons = [...main.querySelectorAll('.feedback-target-cancellation-button')];
        const rects = buttons.map(button => button.getBoundingClientRect());
        return style.backgroundColor === 'rgb(255, 255, 255)' && style.color === 'rgb(31, 31, 31)' &&
          style.fontFamily.includes('Noto Sans JP') &&
          getComputedStyle(main.querySelector('.feedback-target-cancellation-date')).fontSize === '22px' &&
          [...main.querySelectorAll('.feedback-target-cancellation-warning p')].every(element => {
            const text = getComputedStyle(element);
            return text.fontSize === '20px' && text.fontWeight === '400' &&
              text.color === 'rgb(0, 0, 0)' && text.textDecorationLine === 'none';
          }) && buttons.length === 2 && buttons.every(button => #{button_style_check}) &&
          Math.abs(rects[0].top - rects[1].top) <= 1 && Math.abs(rects[0].bottom - rects[1].bottom) <= 1 &&
          rects[0].right + 11 <= rects[1].left && rects.every(rect => rect.width > 0 && rect.height >= 46);
      })()
    JS
  end

  def button_style_check
    <<~JS.squish
      (() => {
        const buttonStyle = getComputedStyle(button);
        return buttonStyle.backgroundColor === 'rgb(237, 237, 237)' && buttonStyle.color === 'rgb(31, 31, 31)' &&
          buttonStyle.fontSize === '14px' && buttonStyle.fontWeight === '400' && buttonStyle.borderRadius === '0px' &&
          buttonStyle.textDecorationLine === 'none' && ['Top', 'Right', 'Bottom', 'Left'].every(side =>
            buttonStyle['border' + side + 'Width'] === '1px' && buttonStyle['border' + side + 'Style'] === 'solid' &&
            buttonStyle['border' + side + 'Color'] === 'rgb(31, 31, 31)');
      })()
    JS
  end

  def assert_configured_positions
    assert_positions("main h2" => [ 60, 167 ], ".feedback-target-setting-date" => [ 60, 222 ],
      ".feedback-target-setting-state" => [ 60, 296 ], ".feedback-target-cancel-link" => [ 223, 466 ])
    assert_in_delta 488, find(".feedback-target-cancel-link").evaluate_script("this.getBoundingClientRect().width"), 0.1
  end

  def assert_confirmation_positions
    # Issueで指定された対象料理の1行分（48px）をFigmaの案内の前に追加する。
    assert_positions(".feedback-target-cancellation-date" => [ 92, 222 ],
      ".feedback-target-cancellation-warning" => [ 92, 296 ],
      ".feedback-target-cancellation-actions a" => [ 92, 534 ],
      ".feedback-target-cancellation-actions button" => [ 570, 534 ])
    assert_in_delta 310, find(".feedback-target-cancellation-actions button").evaluate_script("this.getBoundingClientRect().width"), 0.1
  end

  def assert_positions(positions)
    positions.each do |selector, (x, y)|
      rect = find(selector).evaluate_script("this.getBoundingClientRect().toJSON()")
      assert_in_delta x, rect.fetch("left"), 0.1, "#{selector} differs horizontally"
      assert_in_delta y, rect.fetch("top"), 0.1, "#{selector} differs vertically"
    end
  end

  def save_screen(state, width)
    page.save_screenshot(Rails.root.join("tmp/screenshots/issue73-#{state}-#{width}.png")) if [ 390, 960 ].include?(width)
  end
end
