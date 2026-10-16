require "test_helper"

class TermsTest < ActionDispatch::SystemTestCase
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

    @kindergarten_user = User.create!(login_id: "TermsKindergarten", password: "terms-password", role: :kindergarten,
      kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
    @center_user = User.create!(login_id: "TermsCenter", password: "terms-password", role: :center)
  end

  test "logged out users open terms from the footer and return to TOP" do
    visit root_path
    within "footer" do
      click_link "利用規約"
    end

    assert_current_path terms_path
    assert_public_layout
    assert_selector ".terms-navigation a", exact_text: "TOP", count: 1
    assert_responsive_design(:logged_out)

    click_link "TOP"

    assert_current_path root_path
    assert_selector "header", count: 1
    assert_selector "footer", count: 1
    within "footer" do
      assert_link "プライバシーポリシー", href: privacy_policy_path
    end

    visit terms_path
    assert_public_layout
    assert_selector ".terms-navigation a", exact_text: "TOP", count: 1
  end

  test "kindergarten users access terms directly and use both navigation links" do
    log_in(@kindergarten_user, kindergarten_login_path)
    visit terms_path

    assert_public_layout
    assert_no_link "TOP"
    assert_responsive_design(:kindergarten)

    { "入力・編集" => new_reaction_path, "集計結果" => reactions_path }.each do |label, path|
      visit terms_path
      within ".terms-navigation" do
        click_link label
      end

      assert_current_path path
      assert_selector "header", count: 1
      assert_selector "footer", count: 1
      within "footer" do
        click_link "利用規約"
      end
      assert_current_path terms_path
      assert_selector ".terms-navigation--kindergarten a", count: 2
      assert_public_layout
    end
  end

  test "center users access terms directly and use all three navigation links" do
    log_in(@center_user, center_login_path)
    visit terms_path

    assert_public_layout
    assert_no_link "TOP"
    assert_responsive_design(:center)

    { "集計結果" => center_reaction_results_path, "対象料理設定" => new_feedback_target_path,
      "料理マスタ登録" => new_dish_path }.each do |label, path|
      visit terms_path
      within ".terms-navigation" do
        click_link label
      end

      assert_current_path path
      assert_selector "header", count: 1
      assert_selector "footer", count: 1
      within "footer" do
        click_link "利用規約"
      end
      assert_current_path terms_path
      assert_selector ".terms-navigation--center a", count: 3
      assert_public_layout
    end
  end

  test "the full manuscript scrolls with the document and the final text and navigation remain reachable" do
    visit terms_path
    assert_noto_sans_jp_loaded

    [ 320, 360, 390, 960, 1200 ].each do |width|
      resize_viewport(width)
      assert_fits_viewport(width)
      assert_document_scroll(width)
    end
  end

  private

  def log_in(user, login_path)
    visit login_path
    fill_in "ログインID", with: user.login_id
    fill_in "パスワード", with: "terms-password"
    click_button "ログイン"
    assert_selector "header.shared-header--after-login"
    assert_noto_sans_jp_loaded
  end

  def assert_public_layout
    assert_selector "main h1", exact_text: "利用規約"
    assert_selector ".terms-body > section", count: 10
    assert_selector ".terms-body > section > h2", count: 10
    assert_selector ".terms-body > section:last-of-type h2", exact_text: "第10条（利用者に関する情報の取扱い）"
    assert_selector ".terms-body time[datetime='2026-10-16']", exact_text: "2026年10月16日", count: 2
    assert_no_text "ダミーテキスト"
    assert_no_text "別タスクで作成"
    assert_no_text "概要："
    assert_no_text "【公開前要確認】"
    assert_no_text "【正式公開時に確定】"
    assert_no_selector "header, footer"
    assert_no_text "表示状態："
    assert_no_text "ナビゲーションはログイン状態"
    assert_no_text "優先環境："
    assert_no_text "優先事項："
  end

  def resize_viewport(width)
    height = width >= 861 ? 720 : 844
    browser = page.driver.browser
    browser.manage.window.resize_to(width, height)
    chrome_height = height - page.evaluate_script("window.innerHeight")
    browser.manage.window.resize_to(width, height + chrome_height)
    assert_equal width, page.evaluate_script("window.innerWidth")
    assert_equal height, page.evaluate_script("window.innerHeight")
    page.execute_script("window.scrollTo({ top: 0, behavior: 'instant' })")
  end

  def assert_responsive_design(role)
    assert_noto_sans_jp_loaded

    [ 320, 360, 390, 767, 768, 860, 861, 960, 1200 ].each do |width|
      resize_viewport(width)
      assert_fits_viewport(width)
      assert page.evaluate_script(<<~JS), "Terms layout differs from the approved design for #{role} at #{width}px"
        (() => {
          const main = document.querySelector('main');
          const heading = main.querySelector('h1');
          const body = main.querySelector('.terms-body');
          const navigation = main.querySelector('.terms-navigation');
          const buttons = [...navigation.querySelectorAll('a')];
          const rects = buttons.map(button => button.getBoundingClientRect());
          const style = getComputedStyle(main);
          const borderMatches = element => ['Top', 'Right', 'Bottom', 'Left'].every(side => {
            const s = getComputedStyle(element);
            return s['border' + side + 'Width'] === '1px' && s['border' + side + 'Style'] === 'solid' &&
              s['border' + side + 'Color'] === 'rgb(31, 31, 31)';
          });
          const viewportWidth = document.documentElement.clientWidth;
          const center = rect => Math.abs((rect.left + rect.right) / 2 - viewportWidth / 2) < 1;
          const expectedWidth = '#{role}' === 'kindergarten' ? Math.min((viewportWidth - 50 - 14) / 2, 261) :
            '#{role}' === 'center' && #{width} >= 861 ? Math.min((viewportWidth - 50 - 28) / 3, 261) :
            Math.min(viewportWidth - 50, 261);
          const vertical = '#{role}' === 'center' && #{width} < 861;
          return style.backgroundColor === 'rgb(255, 255, 255)' && style.color === 'rgb(31, 31, 31)' &&
            style.fontFamily.includes('Noto Sans JP') && style.fontWeight === '400' && borderMatches(main) &&
            getComputedStyle(heading).fontSize === '24px' && getComputedStyle(heading).fontWeight === '400' &&
            heading.getBoundingClientRect().left === 25 && heading.getBoundingClientRect().top === 77 &&
            body.getBoundingClientRect().left === 25 && body.getBoundingClientRect().top === 130 &&
            body.getBoundingClientRect().width === viewportWidth - 50 && borderMatches(body) &&
            getComputedStyle(body).padding === '18px' && getComputedStyle(body).rowGap === '23.2px' &&
            [...body.querySelectorAll('p, li, h3, code, time')].every(p => getComputedStyle(p).fontSize === '14px' &&
              getComputedStyle(p).fontWeight === '400' && getComputedStyle(p).color === 'rgb(31, 31, 31)' &&
              Math.abs(parseFloat(getComputedStyle(p).lineHeight) - 22.4) < 0.05) &&
            [...body.querySelectorAll('h2')].every(h => getComputedStyle(h).fontSize === '16px' &&
              getComputedStyle(h).fontWeight === '400') &&
            [...body.querySelectorAll('section > * + *, :scope > div > * + *, li > ul, li > ol')].every(p =>
              getComputedStyle(p).marginTop === '8px') &&
            [...body.querySelectorAll('ul, ol')].every(list => getComputedStyle(list).paddingLeft === '24px' &&
              getComputedStyle(list).marginBottom === '0px') &&
            [...body.querySelectorAll('li + li')].every(li => getComputedStyle(li).marginTop === '4px') &&
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
      assert_document_scroll(width)
      if [ 390, 960 ].include?(width)
        page.save_screenshot(Rails.root.join("tmp/screenshots/issue102-terms-#{role}-#{width}-bottom.png"))
        page.execute_script("window.scrollTo({ top: 0, behavior: 'instant' })")
        page.save_screenshot(Rails.root.join("tmp/screenshots/issue102-terms-#{role}-#{width}-top.png"))
      end
    end
  end

  def assert_document_scroll(width)
    assert page.evaluate_script(<<~JS), "The manuscript must use document scrolling at #{width}px"
      (() => {
        const body = document.querySelector('.terms-body');
        const ancestors = [];
        for (let element = body; element && element !== document.body; element = element.parentElement) {
          ancestors.push(element);
        }
        return document.scrollingElement.scrollHeight > window.innerHeight &&
          ancestors.every(element => !['auto', 'scroll', 'hidden', 'clip'].includes(getComputedStyle(element).overflowY)) &&
          body.scrollHeight <= body.clientHeight + 1;
      })()
    JS
    page.execute_script("window.scrollTo({ top: document.scrollingElement.scrollHeight, behavior: 'instant' })")
    assert page.evaluate_script(<<~JS), "The final text or navigation is unreachable at #{width}px"
      (() => {
        const body = document.querySelector('.terms-body').getBoundingClientRect();
        const last = document.querySelector('.terms-body > div:last-child > p:last-child').getBoundingClientRect();
        const navigation = document.querySelector('.terms-navigation').getBoundingClientRect();
        return window.scrollY > 0 && last.top >= 0 && last.bottom <= body.bottom - 18 &&
          navigation.top >= body.bottom + 24 - 1 && navigation.bottom <= window.innerHeight &&
          [...document.querySelectorAll('.terms-navigation a')].every(button => {
            const rect = button.getBoundingClientRect();
            return rect.top >= 0 && rect.bottom <= window.innerHeight;
          });
      })()
    JS
  end

  def assert_fits_viewport(width)
    overflows = page.evaluate_script(<<~JS)
      (() => {
        const failures = [];
        if (document.documentElement.scrollWidth > document.documentElement.clientWidth) failures.push('document');
        [...document.querySelectorAll('main, main h1, .terms-body, .terms-body section, .terms-body h2, .terms-body h3, .terms-body p, .terms-body ul, .terms-body ol, .terms-body li, .terms-navigation, .terms-navigation a')].forEach(element => {
          const rect = element.getBoundingClientRect();
          if (rect.left < 0 || rect.right > document.documentElement.clientWidth + 1) {
            failures.push({ element: element.tagName + '.' + element.className, left: rect.left, right: rect.right,
              scrollWidth: element.scrollWidth, clientWidth: element.clientWidth });
          }
          if (!['A', 'P', 'H1', 'H2', 'H3', 'LI'].includes(element.tagName)) return;
          const container = element.closest('.terms-body')?.getBoundingClientRect() || rect;
          const range = document.createRange();
          range.selectNodeContents(element);
          // 禁則処理による句読点・括弧のぶら下がりも、余白を含む本文枠内なら切れていない。
          if ([...range.getClientRects()].some(text => text.left < container.left || text.right > container.right ||
              (element.tagName !== 'H1' && (text.top < container.top || text.bottom > container.bottom)))) {
            failures.push({ element: element.tagName + '.' + element.className, text: 'outside container' });
          }
        });
        return failures;
      })()
    JS
    assert_empty overflows, "Terms overflow or clip text at #{width}px: #{overflows.inspect}"
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
    assert result.fetch("loaded"), "Noto Sans JP did not load for terms: #{result.inspect}"
  end
end
