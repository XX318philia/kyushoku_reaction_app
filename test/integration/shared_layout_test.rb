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
        assert_select "a[href='#']", text: "入力・編集", count: 1
        assert_select "a[href='#']", text: "集計結果", count: 1
        assert_select "button[aria-controls=kindergarten-menu-items][aria-expanded=false]"
        assert_select "#kindergarten-menu-items a[href='#']", text: "ログアウト", count: 1
      end
      assert_select "header nav[aria-label=?]", "給食センター用ナビゲーション", count: 0
      assert_select "header h1", count: 0
      assert_select "header a.active", count: 0
      assert_shared_footer
    end
  end

  test "center header displays the fixed center name and placeholder navigation on every page" do
    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "center-password" }

    shared_pages.each do |path|
      get path

      assert_response :success
      assert_select "header nav[aria-label=?]", "給食センター用ナビゲーション" do
        assert_select "span", text: "Philia給食センター"
        [ "当日集計結果", "対象料理設定", "料理マスタ登録", "ログアウト" ].each do |label|
          assert_select "a[href='#']", text: label, count: 1
        end
      end
      assert_select "header nav[aria-label=?]", "幼稚園用ナビゲーション", count: 0
      assert_select "header h1", count: 0
      assert_select "header a.active", count: 0
      assert_shared_footer
    end
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
