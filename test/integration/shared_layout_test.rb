require "test_helper"

class SharedLayoutTest < ActionDispatch::IntegrationTest
  test "logged out pages share a single service header and footer" do
    shared_pages.each do |path|
      get path

      assert_response :success
      assert_select "header", count: 1
      assert_select "header h1", text: "給食リアクション", count: 1
      assert_select "main h1", count: 0
      assert_select "header nav", count: 0
      assert_shared_footer
    end
  end

  test "kindergarten header displays the logged in user's kindergarten on every page" do
    kindergarten = Kindergarten.create!(name: "ひまわり幼稚園")
    user = User.create!(login_id: "Himawari", password: "kindergarten-password",
      role: :kindergarten, kindergarten: kindergarten)
    post kindergarten_login_path, params: { login_id: user.login_id, password: "kindergarten-password" }

    shared_pages.each do |path|
      get path

      assert_response :success
      assert_select "header nav[aria-label=?]", "幼稚園用ナビゲーション" do
        assert_select "span", text: kindergarten.name
        assert_select "a[href=?]", new_reaction_path, text: "入力・編集", count: 1
        assert_select "a[href='#']", text: "集計結果", count: 1
        assert_select "button[aria-controls=kindergarten-menu-items][aria-expanded=false]"
        assert_select "a[href=?][data-turbo-method=delete].d-none.d-md-block", kindergarten_logout_path, text: "ログアウト", count: 1
        assert_select "#kindergarten-menu-items a[href=?][data-turbo-method=delete]", kindergarten_logout_path, text: "ログアウト", count: 1
        assert_select "a[href=?]", center_logout_path, count: 0
      end
      assert_select "header nav[aria-label=?]", "給食センター用ナビゲーション", count: 0
      assert_select "header h1", count: 0
      assert_select "header a.active", count: 0
      assert_shared_footer
    end
  end

  test "center header displays the fixed center name and implemented navigation links on every page" do
    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "center-password" }

    shared_pages.each do |path|
      get path

      assert_response :success
      assert_select "header nav[aria-label=?]", "給食センター用ナビゲーション" do
        assert_select "span", text: "Philia給食センター"
        assert_select "a[href='#']", text: "当日集計結果", count: 1
        assert_select "a[href=?]", new_feedback_target_path, text: "対象料理設定", count: 1
        assert_select "a[href=?]", new_dish_path, text: "料理マスタ登録", count: 1
        assert_select "a[href=?][data-turbo-method=delete]", center_logout_path, text: "ログアウト", count: 1
        assert_select "a[href=?]", kindergarten_logout_path, count: 0
      end
      assert_select "header nav[aria-label=?]", "幼稚園用ナビゲーション", count: 0
      assert_select "header h1", count: 0
      assert_select "header a.active", count: 0
      assert_shared_footer
    end
  end

  test "kindergarten reaction entry link opens the page with the shared header and footer" do
    user = User.create!(login_id: "Sakura", password: "kindergarten-password", role: :kindergarten,
      kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
    post kindergarten_login_path, params: { login_id: user.login_id, password: "kindergarten-password" }
    get root_path

    assert_select "header a[href=?].nav-link", new_reaction_path, text: "入力・編集", count: 1

    get new_reaction_path

    assert_response :success
    assert_select "h2", text: "入力フォーム", count: 1
    assert_select "header.shared-header.shared-header--after-login", count: 1
    assert_select "header nav[aria-label=?]", "幼稚園用ナビゲーション", count: 1
    assert_shared_footer
  end

  test "center dish registration link opens the form with the shared header and footer" do
    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "center-password" }
    get root_path

    assert_select "header a[href=?].nav-link", new_dish_path, text: "料理マスタ登録", count: 1

    get new_dish_path

    assert_response :success
    assert_select "h2", text: "登録フォーム", count: 1
    assert_select "form[action=?]", dishes_path, count: 1
    assert_select "header.shared-header.shared-header--after-login", count: 1
    assert_select "header nav[aria-label=?]", "給食センター用ナビゲーション", count: 1
    assert_select "header a.active", count: 0
    assert_shared_footer
  end

  test "center feedback target link opens the form with the shared header and footer" do
    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    Dish.create!(name: "カレー", category: :main_dish)
    post center_login_path, params: { login_id: user.login_id, password: "center-password" }
    get root_path

    assert_select "header a[href=?].nav-link", new_feedback_target_path, text: "対象料理設定", count: 1

    get new_feedback_target_path

    assert_response :success
    assert_select "h2", text: "設定フォーム", count: 1
    assert_select "form[action=?]", feedback_targets_path, count: 1
    assert_select "header.shared-header.shared-header--after-login", count: 1
    assert_select "header nav[aria-label=?]", "給食センター用ナビゲーション", count: 1
    assert_select "header a.active", count: 0
    assert_shared_footer
  end

  test "failed login keeps the shared logged out header and footer" do
    [ kindergarten_login_path, center_login_path ].each do |path|
      post path, params: { login_id: "unknown", password: "wrong-password" }

      assert_response :unprocessable_content
      assert_select "header h1", text: "給食リアクション", count: 1
      assert_select "[role=alert]", text: "ログインIDまたはパスワードが正しくありません"
      assert_shared_footer
    end
  end

  test "logout restores the shared logged out header and footer for both roles" do
    kindergarten_user = User.create!(login_id: "Himawari", password: "layout-password", role: :kindergarten,
      kindergarten: Kindergarten.create!(name: "ひまわり幼稚園"))
    center_user = User.create!(login_id: "Center", password: "layout-password", role: :center)

    [ [ kindergarten_user, kindergarten_login_path, kindergarten_logout_path ],
      [ center_user, center_login_path, center_logout_path ] ].each do |user, login_path, logout_path|
      post login_path, params: { login_id: user.login_id, password: "layout-password" }
      get root_path
      assert_select "header nav", count: 1

      delete logout_path

      assert_response :see_other
      assert_redirected_to login_path
      follow_redirect!

      shared_pages.each do |path|
        get path

        assert_response :success
        assert_select "header", count: 1
        assert_select "header h1", text: "給食リアクション", count: 1
        assert_select "header nav", count: 0
        assert_select "header a[data-turbo-method=delete]", count: 0
        assert_shared_footer
      end
    end
  end

  private

  def shared_pages
    [ root_path, kindergarten_login_path, center_login_path ]
  end

  def assert_shared_footer
    assert_select "footer", count: 1
    assert_select "footer a[href='#']", text: "利用規約", count: 1
    assert_select "footer a[href='#']", text: "プライバシーポリシー", count: 1
  end
end
