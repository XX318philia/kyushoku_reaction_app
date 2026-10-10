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

  test "login and header navigation open responsive count inputs and page operations never save reactions" do
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

      [ 390, 1280 ].each do |width|
        page.driver.browser.manage.window.resize_to(width, 844)
        fill_in "美味しそうに食べていた", with: "12"
        fill_in "普通・どちらでもない", with: "3"
        fill_in "苦手そうに食べていた", with: "1"
        find_field("苦手そうに食べていた").send_keys(:arrow_up)
        assert_field "苦手そうに食べていた", with: "2"
        find_field("苦手そうに食べていた").send_keys(:arrow_down, :enter)
        assert_field "苦手そうに食べていた", with: "1"
        select "年少", from: "担当クラス"
        assert_select "担当クラス", selected: "年少"
        select "年中", from: "担当クラス"
        assert_select "担当クラス", selected: "年中"
        assert_field "美味しそうに食べていた", with: "12"
        assert_field "普通・どちらでもない", with: "3"
        assert_field "苦手そうに食べていた", with: "1"
        assert_current_path new_reaction_path
        assert_no_selector "main form, main button, main input[type=submit]"
        assert page.evaluate_script(<<~JS), "Reaction entry overflows the viewport at #{width}px"
          document.documentElement.scrollWidth <= window.innerWidth &&
          [...document.querySelectorAll('main h2, main p, main select, main label, main input')].every(element => {
            const rect = element.getBoundingClientRect();
            return rect.left >= 0 && rect.right <= window.innerWidth;
          })
        JS
        assert_reaction_count_layout(width)
        assert page.evaluate_script("Math.abs(document.querySelector('footer').getBoundingClientRect().bottom - window.innerHeight) <= 1")
        page.save_screenshot(Rails.root.join("tmp/screenshots/issue31-reactions-#{width}.png"))
      end

      visit root_path
      assert_no_selector "head link[href*='fonts.googleapis.com']", visible: :all
      click_link "入力・編集"
      assert_current_path new_reaction_path
      assert_noto_sans_jp_loaded
      assert_select "担当クラス", selected: "担当クラス"
      assert_field "美味しそうに食べていた", with: "0"
      assert_field "普通・どちらでもない", with: "0"
      assert_field "苦手そうに食べていた", with: "0"
    end

    assert_equal original_attributes, reaction.reload.attributes
  end

  test "long dish and class names fit mobile and desktop widths" do
    @feedback_target.dish.update!(name: "鶏肉とたっぷり野菜のやさしいクリーム煮", category: :fruit_or_dessert)
    @classrooms.first.update!(name: "ひまわり幼稚園の年少さんのさくらクラス")
    visit kindergarten_login_path
    fill_in "ログインID", with: @user.login_id
    fill_in "パスワード", with: "kindergarten-password"
    click_button "ログイン"
    assert_noto_sans_jp_loaded

    [ 390, 1280 ].each do |width|
      page.driver.browser.manage.window.resize_to(width, 844)
      assert_selector ".reaction-entry-dish", text: "鶏肉とたっぷり野菜のやさしいクリーム煮（フルーツ・デザート）"
      select @classrooms.first.name, from: "担当クラス"
      assert_select "担当クラス", selected: @classrooms.first.name
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
      assert page.evaluate_script(<<~JS), "The class selector overlaps a wrapped dish name"
        document.querySelector('#classroom_id').getBoundingClientRect().top >=
          document.querySelector('.reaction-entry-dish').getBoundingClientRect().bottom + 12
      JS
      assert_reaction_count_layout(width)
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue31-reactions-long-#{width}.png"))
    end
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
              Math.abs((rect.left + rect.right) / 2 - window.innerWidth / 2) <= 1 &&
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
      assert_no_selector "main button, main form, main input[type=submit]"
    end
  end

  private

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
    assert page.evaluate_script(<<~JS), "Reaction count inputs differ from the design or overlap at #{width}px"
      (() => {
        let previousRect = document.querySelector('#classroom_id').getBoundingClientRect();
        return [...document.querySelectorAll('.reaction-entry-count')].every(field => {
          const input = field.querySelector('input');
          const label = field.querySelector('label');
          const rect = input.getBoundingClientRect();
          const labelRect = label.getBoundingClientRect();
          const style = getComputedStyle(input);
          const labelStyle = getComputedStyle(label);
          const matches = Math.abs(rect.width - 326) <= 1 && Math.abs(rect.height - 40) <= 1 &&
            Math.abs((rect.left + rect.right) / 2 - window.innerWidth / 2) <= 1 &&
            Math.abs(rect.top - previousRect.bottom - 12) <= 1 &&
            rect.left >= 0 && rect.right <= window.innerWidth &&
            labelRect.left >= rect.left && labelRect.right <= rect.left + parseFloat(style.paddingLeft) &&
            labelRect.top >= rect.top && labelRect.bottom <= rect.bottom &&
            style.backgroundColor === 'rgb(255, 255, 255)' && style.color === 'rgb(31, 31, 31)' &&
            style.fontFamily.includes('Noto Sans JP') && style.fontSize === '11px' &&
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
          return matches;
        });
      })()
    JS
  end
end
