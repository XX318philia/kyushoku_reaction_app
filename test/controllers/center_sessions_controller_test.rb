require "test_helper"

class CenterSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @center_user = User.create!(login_id: "Center", password: "center-password", role: :center)
    @kindergarten_user = User.create!(login_id: "Sakura", password: "kindergarten-password",
      role: :kindergarten, kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
  end

  test "displays the center login form" do
    get center_login_url

    assert_response :success
    assert_select "h1", text: "給食リアクション"
    assert_select "h2", text: "ログイン"
    assert_select "p", text: "こちらは給食センター様用のログインページです。"
    assert_select "form[action=?][method=post]", center_login_path do
      assert_select "label[for=login_id]", text: "ログインID"
      assert_select "input[type=text][name=login_id][autocomplete=username]"
      assert_select "label[for=password]", text: "パスワード"
      assert_select "input[type=password][name=password][autocomplete=current-password]"
      assert_select "input[type=submit][value=ログイン]"
    end
    assert_select "[role=alert]", count: 0
    assert_nil request.session[:user_id]
  end

  test "logs in a center user and redirects to the root" do
    post center_login_url, params: { login_id: @center_user.login_id, password: "center-password" }

    assert_response :see_other
    assert_redirected_to root_url
    assert_equal @center_user.id, request.session[:user_id]

    follow_redirect!

    assert_response :success
    assert_equal @center_user.id, request.session[:user_id]
  end

  test "does not log in with an unknown login id" do
    assert_login_failure(login_id: "unknown", password: "center-password")
  end

  test "does not log in with an incorrect password" do
    assert_login_failure(login_id: @center_user.login_id, password: "wrong-password")
  end

  test "does not log in with empty credentials" do
    assert_login_failure(login_id: "", password: "")
  end

  test "does not log in with an empty login id" do
    assert_login_failure(login_id: "", password: "center-password")
  end

  test "does not log in with an empty password" do
    assert_login_failure(login_id: @center_user.login_id, password: "")
  end

  test "does not log in with missing credentials" do
    assert_login_failure({})
    assert_login_failure(login_id: @center_user.login_id)
    assert_login_failure(password: "center-password")
  end

  test "does not log in a kindergarten user with correct credentials" do
    assert_login_failure(login_id: @kindergarten_user.login_id, password: "kindergarten-password")
  end

  test "does not log in when login id case differs" do
    [ "center", "CENTER" ].each do |login_id|
      assert_login_failure(login_id: login_id, password: "center-password")
    end
  end

  test "does not log in when whitespace is added to the login id" do
    [ " Center", "Center ", " Center ", "\tCenter\n", "　Center　" ].each do |login_id|
      assert_login_failure(login_id: login_id, password: "center-password")
    end
  end

  test "logs in only with an exact match for a login id containing stored whitespace" do
    @center_user.update!(login_id: " Center ")

    assert_login_failure(login_id: "Center", password: "center-password")

    post center_login_url, params: { login_id: @center_user.login_id, password: "center-password" }

    assert_redirected_to root_url
    assert_equal @center_user.id, request.session[:user_id]
  end

  test "retains the entered login id but does not render the password after failure" do
    assert_login_failure(login_id: " Center ", password: "wrong-password")

    assert_select "input[name=login_id][value=?]", " Center "
    assert_select "input[name=password][value]", count: 0
  end

  test "does not carry the login error into the next page request" do
    assert_login_failure(login_id: "unknown", password: "center-password")

    get center_login_url

    assert_response :success
    assert_select "[role=alert]", count: 0
  end

  private

  def assert_login_failure(credentials)
    post center_login_url, params: credentials

    assert_response :unprocessable_content
    assert_nil request.session[:user_id]
    assert_select "[role=alert]", text: "ログインIDまたはパスワードが正しくありません"
    assert_select "form[action=?]", center_login_path
  end
end

class CenterSessionsSessionTest < ActionController::TestCase
  tests CenterSessionsController

  test "successful login uses the shared session reset and current user management" do
    user = User.create!(login_id: "Center", password: "center-password", role: :center)
    session[:previous_value] = "old-session-data"

    post :create, params: { login_id: user.login_id, password: "center-password" }

    assert_redirected_to root_url
    assert_equal user.id, session[:user_id]
    assert_nil session[:previous_value]
    assert_equal user, @controller.send(:current_user)
    assert_equal true, @controller.send(:logged_in?)
    assert_equal true, @controller.send(:center_user?)
    assert_equal false, @controller.send(:kindergarten_user?)
  end
end
