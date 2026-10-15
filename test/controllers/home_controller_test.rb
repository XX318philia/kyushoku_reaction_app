require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "root displays the top page" do
    get root_url

    assert_response :success
    assert_select "header .shared-logo[aria-label=?]", "給食リアクション", count: 1
    assert_select "main h1", text: "給食を作る人と、食べる人をつなぐ。", count: 1
    assert_select "main p", text: "幼稚園の先生が見た園児たちの様子を、給食センターへ。集まったリアクションを集計し、当日の結果を双方で確認できます。"
    assert_select "main a", count: 0
    assert_select "main picture source[media=?][srcset*=?]", "(min-width: 768px)", "home-desktop"
    assert_select "main picture img[src*=?][width=1086][height=1448]", "home-smartphone"
    assert_select "p", text: "ログイン先を選択してください", count: 0
  end

  test "kindergarten login link opens the kindergarten login page" do
    get root_url

    assert_select "header a[href=?]", kindergarten_login_path, text: "幼稚園の先生はこちら"

    get kindergarten_login_path

    assert_response :success
    assert_select "h2", text: "ログイン"
    assert_select "p", text: "こちらは幼稚園様用のログインページです。"
  end

  test "center login link opens the center login page" do
    get root_url

    assert_select "header a[href=?]", center_login_path, text: "給食センターの方はこちら"

    get center_login_path

    assert_response :success
    assert_select "h2", text: "ログイン"
    assert_select "p", text: "こちらは給食センター様用のログインページです。"
  end
end
