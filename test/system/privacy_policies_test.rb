require "test_helper"

class PrivacyPoliciesTest < ActionDispatch::SystemTestCase
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

    @kindergarten_user = User.create!(login_id: "PrivacyKindergarten", password: "privacy-password", role: :kindergarten,
      kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
    @center_user = User.create!(login_id: "PrivacyCenter", password: "privacy-password", role: :center)
  end

  test "logged out users open privacy policy from the footer and return to TOP" do
    visit root_path
    within "footer" do
      click_link "プライバシーポリシー"
    end

    assert_current_path privacy_policy_path
    assert_public_layout
    assert_selector ".privacy-policy-navigation a", exact_text: "TOP", count: 1
    assert_responsive_design(:logged_out)

    click_link "TOP"

    assert_current_path root_path
    assert_selector "header", count: 1
    assert_selector "footer", count: 1
    within "footer" do
      assert_link "利用規約", href: terms_path
    end

    visit privacy_policy_path
    assert_public_layout
    assert_selector ".privacy-policy-navigation a", exact_text: "TOP", count: 1
  end

  test "kindergarten users access privacy policy directly and use both navigation links" do
    log_in(@kindergarten_user, kindergarten_login_path)
    visit privacy_policy_path

    assert_public_layout
    assert_no_link "TOP"
    assert_responsive_design(:kindergarten)

    { "入力・編集" => new_reaction_path, "集計結果" => reactions_path }.each do |label, path|
      visit privacy_policy_path
      within ".privacy-policy-navigation" do
        click_link label
      end

      assert_current_path path
      assert_selector "header", count: 1
      assert_selector "footer", count: 1
      within "footer" do
        click_link "プライバシーポリシー"
      end
      assert_current_path privacy_policy_path
      assert_selector ".privacy-policy-navigation--kindergarten a", count: 2
      assert_public_layout
    end
  end

  test "center users access privacy policy directly and use all three navigation links" do
    log_in(@center_user, center_login_path)
    visit privacy_policy_path

    assert_public_layout
    assert_no_link "TOP"
    assert_responsive_design(:center)

    { "集計結果" => center_reaction_results_path, "対象料理設定" => new_feedback_target_path,
      "料理マスタ登録" => new_dish_path }.each do |label, path|
      visit privacy_policy_path
      within ".privacy-policy-navigation" do
        click_link label
      end

      assert_current_path path
      assert_selector "header", count: 1
      assert_selector "footer", count: 1
      within "footer" do
        click_link "プライバシーポリシー"
      end
      assert_current_path privacy_policy_path
      assert_selector ".privacy-policy-navigation--center a", count: 3
      assert_public_layout
    end
  end

  test "the text area grows to contain long content without clipping or overlapping navigation" do
    visit privacy_policy_path
    assert_noto_sans_jp_loaded

    [ 320, 390, 960 ].each do |width|
      resize_viewport(width)
      original_height = find(".privacy-policy-body").evaluate_script("this.getBoundingClientRect().height")
      page.execute_script(<<~JS)
        document.querySelector('.privacy-policy-body p:last-child').textContent =
          'これは表示確認用の長いダミーテキストです。'.repeat(200);
      JS

      assert_fits_viewport(width)
      assert_operator find(".privacy-policy-body").evaluate_script("this.getBoundingClientRect().height"), :>, original_height
      assert page.evaluate_script(<<~JS), "Long text overlaps navigation at #{width}px"
        (() => {
          const body = document.querySelector('.privacy-policy-body').getBoundingClientRect();
          const text = document.querySelector('.privacy-policy-body p:last-child').getBoundingClientRect();
          const navigation = document.querySelector('.privacy-policy-navigation').getBoundingClientRect();
          return text.bottom <= body.bottom - 18 && navigation.top >= body.bottom + 24;
        })()
      JS
      page.execute_script(<<~JS)
        document.querySelector('.privacy-policy-body p:last-child').textContent = 'プライバシーポリシーの本文は別タスクで作成します。';
      JS
    end
  end

  test "the text area stretches and shrinks with viewport height" do
    visit privacy_policy_path
    assert_noto_sans_jp_loaded
    browser = page.driver.browser

    [ 390, 960 ].each do |width|
      resize_viewport(width)
      original_height = find(".privacy-policy-body").evaluate_script("this.getBoundingClientRect().height")
      original_window = browser.manage.window.size
      browser.manage.window.resize_to(original_window.width, original_window.height + 120)
      grown_height = find(".privacy-policy-body").evaluate_script("this.getBoundingClientRect().height")
      assert_in_delta original_height + 120, grown_height, 1
      assert_fits_viewport(width)

      browser.manage.window.resize_to(original_window.width, original_window.height)
      assert_in_delta original_height, find(".privacy-policy-body").evaluate_script("this.getBoundingClientRect().height"), 1
      assert_fits_viewport(width)
    end
  end

  private

  def log_in(user, login_path)
    visit login_path
    fill_in "ログインID", with: user.login_id
    fill_in "パスワード", with: "privacy-password"
    click_button "ログイン"
    assert_selector "header.shared-header--after-login"
    assert_noto_sans_jp_loaded
  end

  def assert_public_layout
    assert_selector "main h1", exact_text: "プライバシーポリシー"
    assert_selector ".privacy-policy-body p", exact_text: "本文領域（ダミーテキスト）"
    assert_selector ".privacy-policy-body p", exact_text: "プライバシーポリシーの本文は別タスクで作成します。"
    assert_no_selector "header, footer"
    assert_no_text "表示状態："
    assert_no_text "ナビゲーションはログイン状態"
    assert_no_text "URLを直接入力"
    assert_no_text "MVPはダミー本文"
    assert_no_text "横スクロールなし"
    assert_no_text "優先環境："
    assert_no_text "優先事項："
  end

  def resize_viewport(width)
    height = width == 960 ? 720 : 844
    browser = page.driver.browser
    browser.manage.window.resize_to(width, height)
    chrome_height = height - page.evaluate_script("window.innerHeight")
    browser.manage.window.resize_to(width, height + chrome_height)
    assert_equal width, page.evaluate_script("window.innerWidth")
    assert_equal height, page.evaluate_script("window.innerHeight")
  end

  def assert_responsive_design(role)
    assert_noto_sans_jp_loaded

    [ 320, 390, 767, 768, 860, 861, 960 ].each do |width|
      resize_viewport(width)
      assert_fits_viewport(width)
      assert page.evaluate_script(<<~JS), "Privacy policy layout differs from the approved design for #{role} at #{width}px"
        (() => {
          const main = document.querySelector('main');
          const heading = main.querySelector('h1');
          const body = main.querySelector('.privacy-policy-body');
          const navigation = main.querySelector('.privacy-policy-navigation');
          const buttons = [...navigation.querySelectorAll('a')];
          const rects = buttons.map(button => button.getBoundingClientRect());
          const style = getComputedStyle(main);
          const borderMatches = element => ['Top', 'Right', 'Bottom', 'Left'].every(side => {
            const s = getComputedStyle(element);
            return s['border' + side + 'Width'] === '1px' && s['border' + side + 'Style'] === 'solid' &&
              s['border' + side + 'Color'] === 'rgb(31, 31, 31)';
          });
          const center = rect => Math.abs((rect.left + rect.right) / 2 - window.innerWidth / 2) < 1;
          const expectedWidth = '#{role}' === 'kindergarten' ? Math.min((#{width} - 50 - 14) / 2, 261) : 261;
          const vertical = '#{role}' === 'center' && #{width} < 861;
          return style.backgroundColor === 'rgb(255, 255, 255)' && style.color === 'rgb(31, 31, 31)' &&
            style.fontFamily.includes('Noto Sans JP') && style.fontWeight === '400' && borderMatches(main) &&
            getComputedStyle(heading).fontSize === '24px' && getComputedStyle(heading).fontWeight === '400' &&
            heading.getBoundingClientRect().left === 25 && heading.getBoundingClientRect().top === 77 &&
            body.getBoundingClientRect().left === 25 && body.getBoundingClientRect().top === 130 &&
            body.getBoundingClientRect().width === #{width} - 50 && borderMatches(body) &&
            Math.abs(navigation.getBoundingClientRect().top - body.getBoundingClientRect().bottom - 24) < 1 &&
            Math.abs(main.getBoundingClientRect().bottom - navigation.getBoundingClientRect().bottom - 44) < 1 &&
            getComputedStyle(body).padding === '18px' && getComputedStyle(body).rowGap === '23.2px' &&
            [...body.querySelectorAll('p')].every(p => getComputedStyle(p).fontSize === '13px' &&
              getComputedStyle(p).fontWeight === '400' && getComputedStyle(p).color === 'rgb(31, 31, 31)') &&
            buttons.every((button, index) => {
              const s = getComputedStyle(button);
              return Math.abs(rects[index].width - expectedWidth) < 1 && rects[index].height === 65 &&
                s.fontSize === '20px' && s.fontWeight === '400' && s.color === 'rgb(0, 0, 0)' &&
                s.backgroundColor === 'rgb(237, 237, 237)' && s.borderRadius === '0px' &&
                s.textDecorationLine === 'none' && borderMatches(button);
            }) && (vertical ? rects.every((rect, index) => center(rect) &&
              (index === 0 || Math.abs(rect.top - rects[index - 1].bottom - 14) < 1)) :
              center(navigation.getBoundingClientRect()) && rects.every((rect, index) => index === 0 ||
                (Math.abs(rect.top - rects[0].top) < 1 && Math.abs(rect.left - rects[index - 1].right - 14) < 1))) &&
            ('#{role}' !== 'logged_out' || center(rects[0]));
        })()
      JS
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue23-privacy-policy-#{role}-#{width}.png")) if [ 390, 960 ].include?(width)
    end
  end

  def assert_fits_viewport(width)
    overflows = page.evaluate_script(<<~JS)
      (() => {
        const failures = [];
        if (document.documentElement.scrollWidth > window.innerWidth) failures.push('document');
        [...document.querySelectorAll('main, main h1, .privacy-policy-body, .privacy-policy-body p, .privacy-policy-navigation, .privacy-policy-navigation a')].forEach(element => {
          const rect = element.getBoundingClientRect();
          if (rect.left < 0 || rect.right > window.innerWidth + 1 || element.scrollWidth > element.clientWidth + 1) {
            failures.push({ element: element.tagName + '.' + element.className, left: rect.left, right: rect.right,
              scrollWidth: element.scrollWidth, clientWidth: element.clientWidth });
          }
          if (!['A', 'P', 'H1'].includes(element.tagName)) return;
          const container = element.tagName === 'P' ? element.parentElement.getBoundingClientRect() : rect;
          const range = document.createRange();
          range.selectNodeContents(element);
          // 本文の行ボックスからはみ出す字形も、余白を含む本文枠内で表示されれば切れていない。
          if ([...range.getClientRects()].some(text => text.left < container.left || text.right > container.right ||
              (element.tagName !== 'H1' && (text.top < container.top || text.bottom > container.bottom)))) {
            failures.push({ element: element.tagName + '.' + element.className, text: 'outside container' });
          }
        });
        return failures;
      })()
    JS
    assert_empty overflows, "Privacy policy overflow or clip text at #{width}px: #{overflows.inspect}"
  end

  def assert_noto_sans_jp_loaded
    assert_selector "head link[href*='fonts.googleapis.com']", visible: :all, wait: 10
    result = Capybara.using_wait_time(15) do
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1];
        const timer = setTimeout(() => done({ loaded: false, status: document.fonts.status,
          faces: [...document.fonts].reduce((counts, font) => {
            counts[font.status] = (counts[font.status] || 0) + 1;
            return counts;
          }, {}) }), 10000);
        document.fonts.load('400 20px "Noto Sans JP"', document.querySelector('main').textContent).then(fonts => {
          clearTimeout(timer);
          done({ loaded: fonts.length > 0 && fonts.every(font => font.status === 'loaded') });
        }).catch(error => {
          clearTimeout(timer);
          done({ loaded: false, error: String(error) });
        });
      JS
    end
    unless result.fetch("loaded")
      result["browser_errors"] = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" }.map(&:message)
    end
    assert result.fetch("loaded"), "Noto Sans JP did not load for privacy policy: #{result.inspect}"
  end
end
