require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "root displays the top page" do
    get root_url

    assert_response :success
    assert_select "h1", text: "給食リアクション"
    assert_select "p", text: "ログイン先を選択してください"
    assert_select "p", text: "幼稚園様はこちら"
    assert_select "p", text: "給食センター様はこちら"
  end

  test "kindergarten login link opens the kindergarten login page" do
    get root_url

    assert_select "a[href=?]", kindergarten_login_path, text: "幼稚園様はこちら"

    get kindergarten_login_path

    assert_response :success
    assert_select "h2", text: "ログイン"
    assert_select "p", text: "こちらは幼稚園様用のログインページです。"
  end

  test "center login link opens the center login page" do
    get root_url

    assert_select "a[href=?]", center_login_path, text: "給食センター様はこちら"

    get center_login_path

    assert_response :success
    assert_select "h2", text: "ログイン"
    assert_select "p", text: "こちらは給食センター様用のログインページです。"
  end
end
