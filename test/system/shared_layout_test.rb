require "test_helper"

class SharedLayoutSystemTest < ActionDispatch::SystemTestCase
  if ENV["SELENIUM_DRIVER_URL"].present?
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1200, 800 ],
      options: { browser: :remote, url: ENV.fetch("SELENIUM_DRIVER_URL") }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1200, 800 ]
  end

  setup do
    if ENV["SELENIUM_DRIVER_URL"].present?
      Capybara.server_host = "0.0.0.0"
      Capybara.app_host = "http://web:#{Capybara.current_session.server.port}"
    end

    @kindergarten = Kindergarten.create!(name: "とても長い名前のひまわり幼稚園" * 12)
    @kindergarten_user = User.create!(login_id: "LayoutKindergarten", password: "layout-password",
      role: :kindergarten, kindergarten: @kindergarten)
    @center_user = User.create!(login_id: "LayoutCenter", password: "layout-password", role: :center)
    @target = FeedbackTarget.create!(dish: Dish.create!(name: "カレー", category: :main_dish), target_date: Date.current)
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "the top page switches the supplied artwork and login layout at every required width" do
    visit root_path

    widths.each do |width|
      resize_viewport(width)
      assert_shared_design(width)
      assert page.evaluate_script(<<~JS), "Top page artwork or login layout differs at #{width}px"
        (() => {
          const desktop = window.innerWidth >= 768;
          const main = document.querySelector('main');
          const image = main.querySelector('picture img');
          const artworkStyles = [image.parentElement, image].map(element => getComputedStyle(element));
          const picture = image.parentElement.getBoundingClientRect();
          const copy = main.querySelector('.home-hero-copy').getBoundingClientRect();
          const links = [...document.querySelectorAll('.shared-login-link')].map(link => link.getBoundingClientRect());
          const style = getComputedStyle(main.querySelector('h1'));
          return getComputedStyle(main).backgroundColor === 'rgb(255, 248, 236)' &&
            style.color === 'rgb(47, 107, 88)' && style.fontWeight === '700' &&
            style.fontSize === (desktop ? '32px' : '24px') &&
            getComputedStyle(main.querySelector('p')).fontSize === '16px' &&
            image.complete && image.naturalWidth > 0 &&
            artworkStyles.every(style => ['Top', 'Right', 'Bottom', 'Left'].every(side =>
              style['border' + side + 'Width'] === '0px')) &&
            image.currentSrc.includes(desktop ? 'home-desktop' : 'home-smartphone') &&
            Math.abs(image.naturalWidth / image.naturalHeight - (desktop ? 1672 / 941 : 3 / 4)) < 0.001 &&
            Math.abs(picture.width / picture.height - (desktop ? 632 / 356 : 3 / 4)) < 0.001 &&
            (desktop ? copy.right <= picture.left + 1 : copy.bottom + 19 <= picture.top) &&
            (window.innerWidth < 360 ? links[0].bottom + 3 <= links[1].top :
              Math.abs(links[0].top - links[1].top) < 1 && links[0].right + 7 <= links[1].left);
        })()
      JS
      save_screen("home", width)
    end
  end

  test "both login pages keep their logo design and return to the top page at every required width" do
    visit root_path

    widths.each do |width|
      resize_viewport(width)
      { "幼稚園の先生はこちら" => kindergarten_login_path,
        "給食センターの方はこちら" => center_login_path }.each do |label, path|
        visit root_path
        click_link label

        assert_current_path path
        assert_selector "header .shared-logo", count: 1
        assert_no_selector "header nav"
        assert_selector "header a[href='#{root_path}'][aria-label='TOPページへ戻る']", count: 1
        assert_shared_design(width)
        assert_login_logo_design(width)
        page.save_screenshot(Rails.root.join("tmp/screenshots/issue115-#{path.split('/')[1]}-login-#{width}.png"))

        find_link("TOPページへ戻る", enable_aria_label: true).hover
        assert_login_logo_design(width)
        click_link "TOPページへ戻る", enable_aria_label: true

        assert_current_path root_path
        assert_no_selector "header a .shared-logo"
      end
    end
  end

  test "both login pages return to the top page after a failed login" do
    [ kindergarten_login_path, center_login_path ].each do |path|
      visit path
      fill_in "ログインID", with: "unknown"
      fill_in "パスワード", with: "wrong-password"
      click_button "ログイン"

      assert_selector "[role=alert]", text: "ログインIDまたはパスワードが正しくありません"
      click_link "TOPページへ戻る", enable_aria_label: true

      assert_current_path root_path
      assert_no_selector "[role=alert]"
    end
  end

  test "both login logo links show keyboard focus and open the top page with Enter" do
    [ 390, 960 ].each do |width|
      [ kindergarten_login_path, center_login_path ].each do |path|
        visit path
        resize_viewport(width)
        find("body").send_keys(:tab)

        assert_selector "header a[aria-label='TOPページへ戻る']:focus-visible"
        assert page.evaluate_script(<<~JS), "The logo link has no visible keyboard focus at #{width}px"
          (() => {
            const style = getComputedStyle(document.activeElement);
            return style.outlineStyle !== 'none' && parseFloat(style.outlineWidth) > 0 &&
              style.outlineColor !== 'rgba(0, 0, 0, 0)';
          })()
        JS
        page.save_screenshot(Rails.root.join("tmp/screenshots/issue115-#{path.split('/')[1]}-focus-#{width}.png"))
        find_link("TOPページへ戻る", enable_aria_label: true).send_keys(:enter)

        assert_current_path root_path
      end
    end
  end

  test "kindergarten navigation long names and expanded logout menu fit all required widths" do
    log_in(@kindergarten_user, kindergarten_login_path)

    widths.each do |width|
      resize_viewport(width)
      [ new_reaction_path, reactions_path, root_path ].each do |path|
        visit path
        assert_current_path path
        assert_shared_design(width)
        assert page.evaluate_script(<<~JS), "Facility name wraps or is not truncated at #{width}px"
          (() => {
            const name = document.querySelector('.shared-header-name');
            const style = getComputedStyle(name);
            const rect = name.getBoundingClientRect();
            const logo = document.querySelector('.shared-logo').getBoundingClientRect();
            return style.whiteSpace === 'nowrap' && style.textOverflow === 'ellipsis' &&
              style.overflow === 'hidden' && name.scrollWidth > name.clientWidth && rect.top >= logo.bottom &&
              [...document.querySelectorAll('header a, header button')].filter(element => element.offsetHeight).every(element => {
                const control = element.getBoundingClientRect();
                return control.bottom <= rect.top || control.left >= rect.right || control.right <= rect.left;
              });
          })()
        JS
      end

      save_screen("kindergarten", width)
      if width < 768
        find("#kindergarten-menu").click
        assert_selector "#kindergarten-menu[aria-expanded=true]"
        assert_selector "#kindergarten-menu-items", visible: true
        assert page.evaluate_script(<<~JS), "Expanded menu is clipped or overlaps the page copy at #{width}px"
          (() => {
            const menu = document.querySelector('#kindergarten-menu-items').getBoundingClientRect();
            const copy = document.querySelector('main h1').getBoundingClientRect();
            return menu.left >= 0 && menu.right <= window.innerWidth && menu.bottom <= copy.top;
          })()
        JS
        save_screen("kindergarten-menu", width)
        find("#kindergarten-menu").click
      end
    end

    click_link "入力・編集"
    assert_current_path new_reaction_path
    click_link "集計結果"
    assert_current_path reactions_path
    click_link "ログアウト"
    assert_current_path kindergarten_login_path
    assert_selector "header a[aria-label='TOPページへ戻る']"
    resize_viewport(390)
    log_in(@kindergarten_user, kindergarten_login_path)
    find("#kindergarten-menu").click
    within "#kindergarten-menu-items" do
      click_link "ログアウト"
    end
    assert_current_path kindergarten_login_path
    click_link "TOPページへ戻る", enable_aria_label: true
    assert_current_path root_path
  end

  test "center navigation and logout keep working on all business pages and required widths" do
    log_in(@center_user, center_login_path)

    widths.each do |width|
      resize_viewport(width)
      [ root_path, center_reaction_results_path, new_feedback_target_path, new_dish_path,
        confirm_destroy_feedback_target_path(@target) ].each do |path|
        visit path
        assert_current_path path
        assert_shared_design(width)
      end
      save_screen("center", width)
    end

    { "当日集計結果" => center_reaction_results_path, "対象料理設定" => new_feedback_target_path,
      "料理マスタ登録" => new_dish_path }.each do |label, path|
      click_link label
      assert_current_path path
    end
    click_link "ログアウト"
    assert_current_path center_login_path
    click_link "TOPページへ戻る", enable_aria_label: true
    assert_current_path root_path
  end

  private

  def widths
    [ 320, 360, 390, 960, 1200 ]
  end

  def log_in(user, path)
    visit path
    fill_in "ログインID", with: user.login_id
    fill_in "パスワード", with: "layout-password"
    click_button "ログイン"
    assert_selector "header.shared-header--after-login"
  end

  def resize_viewport(width)
    browser = page.driver.browser
    height = width < 768 ? 851 : 800
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height,
      deviceScaleFactor: 1, mobile: width < 768)
    assert_equal width, page.evaluate_script("window.innerWidth")
  end

  def assert_login_logo_design(width)
    assert page.evaluate_script(<<~JS), "The login logo design differs at #{width}px"
      (() => {
        const desktop = window.innerWidth >= 768;
        const header = document.querySelector('header').getBoundingClientRect();
        const link = document.querySelector('header a');
        const logo = link.querySelector('.shared-logo');
        const rect = logo.getBoundingClientRect();
        const linkRect = link.getBoundingClientRect();
        const style = getComputedStyle(logo);
        return header.height === 80 && rect.left === (desktop ? 27 : 19) &&
          rect.top === (desktop ? 23 : 28.5) && rect.height === (desktop ? 33 : 22) &&
          ['x', 'y', 'width', 'height'].every(key => rect[key] === linkRect[key]) &&
          style.color === 'rgb(47, 107, 88)' && style.fontSize === (desktop ? '22px' : '14px') &&
          style.fontWeight === '700' && style.gap === '3px' &&
          [link, logo, ...logo.querySelectorAll('.shared-logo-word')].every(element =>
            getComputedStyle(element).textDecorationLine === 'none');
      })()
    JS
  end

  def assert_shared_design(width)
    assert page.evaluate_async_script(<<~JS), "The shared Noto Sans JP font did not load"
      const done = arguments[arguments.length - 1];
      document.fonts.load('700 14px "Noto Sans JP"', '給食リアクション').then(fonts =>
        done(fonts.length > 0 && fonts.every(font => font.status === 'loaded'))).catch(() => done(false));
    JS
    if page.current_path == root_path
      assert_selector ".home-hero-artwork img" do |image|
        image.evaluate_script("this.complete && this.currentSrc.includes('#{width < 768 ? "home-smartphone" : "home-desktop"}')")
      end
    end
    geometry = page.evaluate_script(<<~JS)
      ({ media: matchMedia('(min-width: 768px)').matches,
        image: document.querySelector('main img')?.currentSrc,
        dimensions: [...document.querySelectorAll('.shared-logo, .shared-logo-word, .shared-logo img, header, main, footer')].map(element =>
          ({ tag: element.tagName, class: element.className, rect: element.getBoundingClientRect().toJSON(),
            naturalWidth: element.naturalWidth, background: getComputedStyle(element).backgroundColor })) })
    JS
    assert page.evaluate_script(<<~JS), "Shared colors, assets or layout differ at #{width}px on #{page.current_path}: #{geometry.inspect}"
      (() => {
        const header = document.querySelector('header');
        const footer = document.querySelector('footer');
        const main = document.querySelector('main');
        const logo = header.querySelector('.shared-logo');
        const headerStyle = getComputedStyle(header);
        const footerStyle = getComputedStyle(footer);
        const logoRect = logo.getBoundingClientRect();
        const image = [...logo.querySelectorAll('img')].find(element => element.offsetHeight);
        const text = [...logo.querySelectorAll('.shared-logo-word')].map(element => element.getBoundingClientRect());
        return document.documentElement.scrollWidth <= window.innerWidth &&
          headerStyle.backgroundColor === 'rgb(255, 248, 236)' &&
          footerStyle.backgroundColor === 'rgb(247, 240, 228)' &&
          headerStyle.borderBottom === '1px solid rgb(209, 209, 209)' &&
          footerStyle.borderTop === '1px solid rgb(209, 209, 209)' &&
          getComputedStyle(document.body).backgroundColor === 'rgb(255, 255, 255)' &&
          logoRect.width === (window.innerWidth < 768 ? 140 : 220) &&
          image.complete && image.naturalWidth === (window.innerWidth < 768 ? 22 : 32) &&
          text[0].right <= image.getBoundingClientRect().left && image.getBoundingClientRect().right <= text[1].left &&
          text[1].right <= logoRect.right &&
          [...document.querySelectorAll('header, header a, header button, footer, footer a, main, main img')].every(element => {
            if (!element.offsetHeight) return true;
            const rect = element.getBoundingClientRect();
            return rect.left >= -1 && rect.right <= window.innerWidth + 1;
          }) && header.getBoundingClientRect().bottom <= main.getBoundingClientRect().top + 1 &&
          main.getBoundingClientRect().bottom <= footer.getBoundingClientRect().top + 1;
      })()
    JS
  end

  def save_screen(state, width)
    page.save_screenshot(Rails.root.join("tmp/screenshots/issue101-#{state}-#{width}.png"))
  end
end
