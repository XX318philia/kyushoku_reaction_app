require "test_helper"

class CenterReactionResultsTest < ActionDispatch::SystemTestCase
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

    @user = User.create!(login_id: "CenterResults", password: "center-password", role: :center)
    @dish = Dish.create!(name: "カレー", category: :main_dish)
    kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    @classrooms = [ "年少", "年中" ].map { |name| kindergarten.classrooms.create!(name: name) }
    @classrooms << Kindergarten.create!(name: "ひまわり幼稚園").classrooms.create!(name: "年少")
  end

  test "login and header show responsive unset and zero results while preserving the shared layout" do
    log_in
    assert_current_path center_reaction_results_path
    assert_noto_sans_jp_loaded
    assert_selector "main time", text: Date.current.strftime("%Y年%-m月%-d日")
    assert_selector ".center-reaction-results-unset-notice p:first-child", exact_text: "本日のフィードバック対象料理は、まだ設定されていません。"
    assert_selector ".center-reaction-results-unset-notice p:last-child", exact_text: "『対象料理設定画面』で設定を完了させてください。"
    assert_no_selector ".center-reaction-results-grid, .center-reaction-results-dish, .center-reaction-results-notes"

    [ 320, 390, 767, 768, 960, 1280 ].each do |width|
      resize_viewport(width)
      visit root_path
      shared_layout = shared_layout_styles
      click_link "当日集計結果"
      assert_current_path center_reaction_results_path
      assert_selector ".center-reaction-results-unset-notice"
      assert_no_selector ".center-reaction-results-notes"
      assert_equal shared_layout, shared_layout_styles
      assert_fits_viewport(width)
      assert_frame_positions(unset: true) if width == 960
      assert page.evaluate_script(<<~JS), "Unset guidance differs from the approved design at #{width}px"
        [...document.querySelectorAll('.center-reaction-results-unset-notice, .center-reaction-results-unset-notice p')].every(element => {
          const style = getComputedStyle(element);
          return style.fontSize === '20px' && style.fontWeight === '400' &&
            style.color === 'rgb(0, 0, 0)' && style.textDecorationLine === 'none';
        }) && getComputedStyle(document.querySelector('.center-reaction-results-unset-notice p + p')).marginTop === '20px'
      JS
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue37-center-results-unset-#{width}.png")) if [ 390, 960 ].include?(width)
    end

    FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    page.refresh
    assert_selector ".center-reaction-results-dish", text: "対象料理：カレー"
    assert_no_selector ".center-reaction-results-unset-notice"
    assert_selector ".center-reaction-results-count .center-reaction-results-value", exact_text: "0人 / -", count: 3
    assert_selector ".center-reaction-results-total .center-reaction-results-value", exact_text: "0人"

    [ 320, 390, 767, 768, 960, 1280 ].each do |width|
      resize_viewport(width)
      assert_fits_viewport(width)
      assert_results_design(width)
      assert_frame_positions if width == 960
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue37-center-results-zero-#{width}.png")) if [ 390, 960 ].include?(width)
    end
  end

  test "setting a target opens all class results and only refreshing reflects new counts without writes" do
    log_in
    click_link "対象料理設定"
    select "カレー（主菜）", from: "対象料理"
    click_button "設定"
    assert_current_path center_reaction_results_path
    assert_selector ".center-reaction-results-dish", text: "対象料理：カレー"

    target = FeedbackTarget.find_by!(target_date: Date.current)
    reactions = @classrooms.zip([ [ 2, 1, 0 ], [ 1, 1, 1 ], [ 1, 0, 2 ] ]).map do |classroom, counts|
      create_reaction(classroom, target, counts)
    end
    assert_selector ".center-reaction-results-total .center-reaction-results-value", exact_text: "0人"
    original_data = stored_data
    page.refresh
    assert_result "美味しそうに食べていた", "4人 / 44.4%"
    assert_result "普通・どちらでもない", "2人 / 22.2%"
    assert_result "苦手そうに食べていた", "3人 / 33.3%"
    assert_selector ".center-reaction-results-total .center-reaction-results-value", exact_text: "9人"
    assert_selector ".center-reaction-results-notes p", count: 2
    assert_selector ".center-reaction-results-notes p:first-child", exact_text: "※ 最新の集計を確認したい場合は、ページを再読み込みしてください。"
    assert_selector ".center-reaction-results-notes p:last-child", exact_text: "※ 各割合は小数第1位まで四捨五入して表示しているため、合計が100.0%にならない場合があります。"
    assert_no_text "計算方法の不整合"

    [ 390, 960 ].each do |width|
      resize_viewport(width)
      assert_fits_viewport(width)
      assert_results_design(width)
      assert_frame_positions if width == 960
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue37-center-results-#{width}.png"))
    end
    assert_equal original_data, stored_data

    reactions.first.update!(positive_count: 3)
    assert_selector ".center-reaction-results-total .center-reaction-results-value", exact_text: "9人"
    updated_data = stored_data
    page.refresh
    assert_result "美味しそうに食べていた", "5人 / 50.0%"
    assert_result "普通・どちらでもない", "2人 / 20.0%"
    assert_result "苦手そうに食べていた", "3人 / 30.0%"
    assert_selector ".center-reaction-results-total .center-reaction-results-value", exact_text: "10人"
    assert_equal updated_data, stored_data
  end

  test "long dish names and large zero and one hundred percent results fit mobile and desktop" do
    @dish.update!(name: "鶏肉とたっぷり野菜のやさしいクリーム煮")
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    @classrooms.first(2).each { |classroom| create_reaction(classroom, target, [ 2_147_483_647, 0, 0 ]) }
    log_in
    assert_noto_sans_jp_loaded
    assert_result "美味しそうに食べていた", "4294967294人 / 100.0%"
    assert_result "普通・どちらでもない", "0人 / 0.0%"
    assert_result "苦手そうに食べていた", "0人 / 0.0%"
    assert_selector ".center-reaction-results-total .center-reaction-results-value", exact_text: "4294967294人"

    [ 320, 390, 767, 768, 960, 1280 ].each do |width|
      resize_viewport(width)
      assert_fits_viewport(width)
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue37-center-results-long-#{width}.png")) if [ 390, 960 ].include?(width)
    end
  end

  test "access alert fits below the results heading and disappears with and without a target" do
    target = FeedbackTarget.create!(dish: @dish, target_date: Date.current)
    log_in

    [ true, false ].each do |target_set|
      target.destroy! unless target_set

      [ 320, 390, 960, 1280 ].each do |width|
        resize_viewport(width)
        visit new_reaction_path

        assert_current_path center_reaction_results_path
        assert_selector ".center-reaction-results-content > h2 + .alert.alert-danger[role=alert]",
          exact_text: "このページにはアクセスできません", count: 1
        assert_selector ".center-reaction-results-unset-notice", count: target_set ? 0 : 1
        assert_fits_viewport(width)
        assert page.evaluate_script(<<~JS), "Access alert overflows or overlaps the results content at #{width}px"
          (() => {
            const element = document.querySelector('main .alert[role=alert]');
            const alert = element.getBoundingClientRect();
            const content = document.querySelector('.center-reaction-results-content').getBoundingClientRect();
            const heading = document.querySelector('main h2').getBoundingClientRect();
            const date = document.querySelector('.center-reaction-results-date').getBoundingClientRect();
            return element.scrollWidth <= element.clientWidth &&
              alert.left >= content.left && alert.right <= content.right &&
              alert.top >= heading.bottom && date.top >= alert.bottom;
          })()
        JS
        page.save_screenshot(Rails.root.join("tmp/screenshots/issue53-center-alert-#{target_set ? 'set' : 'unset'}-#{width}.png"))

        visit center_reaction_results_path
        assert_no_selector "main .alert[role=alert]"
      end
    end
  end

  private

  def log_in
    visit center_login_path
    fill_in "ログインID", with: @user.login_id
    fill_in "パスワード", with: "center-password"
    click_button "ログイン"
    assert_selector "main.center-reaction-results"
  end

  def create_reaction(classroom, target, counts)
    Reaction.create!({ classroom: classroom, feedback_target: target }.merge(
      %i[ positive_count neutral_count negative_count ].zip(counts).to_h))
  end

  def stored_data
    [ Reaction, FeedbackTarget, Dish, Classroom, Kindergarten, User ].map { |model| model.order(:id).map(&:attributes) }
  end

  def assert_result(label, value)
    within ".center-reaction-results-count", text: label do
      assert_selector ".center-reaction-results-value", exact_text: value
    end
  end

  def resize_viewport(width)
    # Figmaの960×720pxをブラウザのコンテンツ領域で再現する。
    height = width == 960 ? 720 : 844
    browser = page.driver.browser
    browser.manage.window.resize_to(width, height)
    chrome_height = height - page.evaluate_script("window.innerHeight")
    browser.manage.window.resize_to(width, height + chrome_height)
    assert_equal width, page.evaluate_script("window.innerWidth")
    assert_equal height, page.evaluate_script("window.innerHeight")
  end

  def assert_frame_positions(unset: false)
    positions = if unset
      { ".center-reaction-results-date" => [ 92, 222 ],
        ".center-reaction-results-unset-notice" => [ 92, 259 ] }
    else
      { ".center-reaction-results-date" => [ 40, 222 ],
        ".center-reaction-results-dish" => [ 40, 259 ],
        ".center-reaction-results-count--positive" => [ 40, 296 ],
        ".center-reaction-results-count--neutral" => [ 490, 296 ],
        ".center-reaction-results-count--negative" => [ 40, 386 ],
        ".center-reaction-results-total" => [ 490, 386 ],
        ".center-reaction-results-notes" => [ 40, 469 ] }
    end
    heading = find("main h2").evaluate_script("this.getBoundingClientRect().toJSON()")
    assert_in_delta 167, heading.fetch("top"), 0.1
    assert_in_delta(unset ? 479 : 480, (heading.fetch("left") + heading.fetch("right")) / 2, 0.1)
    positions.each do |selector, (x, y)|
      rect = find(selector).evaluate_script("this.getBoundingClientRect().toJSON()")
      assert_in_delta x, rect.fetch("left"), 0.1, "#{selector} differs from Figma horizontally"
      assert_in_delta y, rect.fetch("top"), 0.1, "#{selector} differs from Figma vertically"
    end
  end

  def shared_layout_styles
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll('header, header nav, header a, footer, footer a')].map(element => {
        const style = getComputedStyle(element);
        return ['backgroundColor', 'color', 'fontSize', 'fontWeight', 'fontFamily',
          'borderTop', 'borderRight', 'borderBottom', 'borderLeft', 'textDecorationLine',
          'padding', 'gap', 'minHeight'].map(property => style[property]);
      })
    JS
  end

  def assert_fits_viewport(width)
    assert page.evaluate_script(<<~JS), "Center results overflow or overlap at #{width}px"
      document.documentElement.scrollWidth <= window.innerWidth &&
        [...document.querySelectorAll('main h2, main p, .center-reaction-results-label, .center-reaction-results-value')].every(element => {
          const rect = element.getBoundingClientRect();
          return rect.left >= 0 && rect.right <= window.innerWidth + 1 &&
            element.scrollWidth <= element.clientWidth + 1;
        }) && [...document.querySelectorAll('.center-reaction-results-count, .center-reaction-results-total')].every(row => {
          const label = row.querySelector('.center-reaction-results-label').getBoundingClientRect();
          const value = row.querySelector('.center-reaction-results-value').getBoundingClientRect();
          return value.top >= label.bottom && value.bottom <= row.getBoundingClientRect().bottom;
        })
    JS
  end

  def assert_results_design(width)
    assert page.evaluate_script(<<~JS), "Center result layout differs from Figma at #{width}px"
      (() => {
        const main = document.querySelector('main');
        const style = getComputedStyle(main);
        const grid = main.querySelector('.center-reaction-results-grid');
        const rows = [...grid.children];
        const rects = rows.map(row => row.getBoundingClientRect());
        const columns = #{width} < 768 ? 1 : 2;
        return style.backgroundColor === 'rgb(255, 255, 255)' && style.color === 'rgb(31, 31, 31)' &&
          style.fontFamily.includes('Noto Sans JP') && style.fontWeight === '400' &&
          getComputedStyle(main.querySelector('h2')).fontSize === '28px' &&
          getComputedStyle(main.querySelector('h2')).fontWeight === '400' &&
          getComputedStyle(main.querySelector('h2')).color === 'rgb(0, 0, 0)' &&
          getComputedStyle(main.querySelector('.center-reaction-results-date')).fontSize === '22px' &&
          getComputedStyle(main.querySelector('.center-reaction-results-dish')).fontSize === '19px' &&
          getComputedStyle(grid).gridTemplateColumns.split(' ').length === columns &&
          getComputedStyle(grid).columnGap === '30px' && getComputedStyle(grid).rowGap === '16px' &&
          rows.every((row, index) => {
            const rowStyle = getComputedStyle(row);
            const labelStyle = getComputedStyle(row.querySelector('.center-reaction-results-label'));
            const value = row.querySelector('.center-reaction-results-value');
            const valueStyle = getComputedStyle(value);
            const valueRect = value.getBoundingClientRect();
            return Math.abs(rects[index].height - 74) <= 1 &&
              (#{width} < 960 || Math.abs(rects[index].width - 420) <= 1) &&
              rowStyle.backgroundColor === 'rgb(255, 255, 255)' && rowStyle.color === 'rgb(31, 31, 31)' &&
              ['Top', 'Right', 'Bottom', 'Left'].every(side =>
                rowStyle['border' + side + 'Width'] === '1px' && rowStyle['border' + side + 'Style'] === 'solid' &&
                rowStyle['border' + side + 'Color'] === 'rgb(31, 31, 31)') &&
              labelStyle.fontSize === '17px' && valueStyle.fontSize === '20px' &&
              labelStyle.fontWeight === '400' && valueStyle.fontWeight === '400' &&
              labelStyle.textDecorationLine === 'none' && valueStyle.textDecorationLine === 'none' &&
              (#{width} < 960 || Math.abs(valueRect.left - rects[index].left - [202, 216, 205, 192][index]) <= 1);
          }) && (columns === 1 ? rects.every((rect, index) => index === 0 || rect.top >= rects[index - 1].bottom + 16) :
            Math.abs(rects[0].top - rects[1].top) <= 1 && Math.abs(rects[2].top - rects[3].top) <= 1 &&
            Math.abs(rects[1].left - rects[0].right - 30) <= 1 && Math.abs(rects[2].top - rects[0].bottom - 16) <= 1);
      })()
    JS
  end

  def assert_noto_sans_jp_loaded
    assert_selector "head link[href*='fonts.googleapis.com']", visible: :all, wait: 10
    assert page.evaluate_async_script(<<~JS), "Noto Sans JP did not load for the center results"
      const done = arguments[arguments.length - 1];
      document.fonts.load('400 17px "Noto Sans JP"', '美味しそうに食べていた').then(fonts => {
        document.fonts.ready.then(() => done(fonts.length > 0 && fonts.every(font => font.status === 'loaded')));
      }).catch(() => done(false));
    JS
  end
end
