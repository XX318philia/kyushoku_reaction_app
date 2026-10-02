require "test_helper"

class KindergartenSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kindergarten_user = User.create!(login_id: "Sakura", password: "kindergarten-password",
      role: :kindergarten, kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
    @center_user = User.create!(login_id: "Center", password: "center-password", role: :center)
  end

  test "displays the kindergarten login form" do
    get kindergarten_login_url

    assert_response :success
    assert_select "h1", text: "給食リアクション"
    assert_select "h2", text: "ログイン"
    assert_select "p", text: "こちらは幼稚園様用のログインページです。"
    assert_select "form[action=?][method=post]", kindergarten_login_path do
      assert_select "label[for=login_id]", text: "ログインID"
      assert_select "input[type=text][name=login_id][autocomplete=username]"
      assert_select "label[for=password]", text: "パスワード"
      assert_select "input[type=password][name=password][autocomplete=current-password]"
      assert_select "input[type=submit][value=ログイン]"
    end
    assert_select "[role=alert]", count: 0
    assert_nil request.session[:user_id]
  end

  test "logs in a kindergarten user and redirects to the root" do
    post kindergarten_login_url, params: { login_id: @kindergarten_user.login_id, password: "kindergarten-password" }

    assert_response :see_other
    assert_redirected_to root_url
    assert_equal @kindergarten_user.id, request.session[:user_id]

    follow_redirect!

    assert_response :success
    assert_equal @kindergarten_user.id, request.session[:user_id]
  end

  test "does not log in with an unknown login id" do
    assert_login_failure(login_id: "unknown", password: "kindergarten-password")
  end

  test "does not log in with an incorrect password" do
    assert_login_failure(login_id: @kindergarten_user.login_id, password: "wrong-password")
  end

  test "does not log in with empty credentials" do
    assert_login_failure(login_id: "", password: "")
  end

  test "does not log in with an empty login id" do
    assert_login_failure(login_id: "", password: "kindergarten-password")
  end

  test "does not log in with an empty password" do
    assert_login_failure(login_id: @kindergarten_user.login_id, password: "")
  end

  test "does not log in with missing credentials" do
    assert_login_failure({})
    assert_login_failure(login_id: @kindergarten_user.login_id)
    assert_login_failure(password: "kindergarten-password")
  end

  test "does not log in a center user with correct credentials" do
    assert_login_failure(login_id: @center_user.login_id, password: "center-password")
  end

  test "does not log in when login id case differs" do
    [ "sakura", "SAKURA" ].each do |login_id|
      assert_login_failure(login_id: login_id, password: "kindergarten-password")
    end
  end

  test "does not log in when whitespace is added to the login id" do
    [ " Sakura", "Sakura ", " Sakura ", "\tSakura\n", "　Sakura　" ].each do |login_id|
      assert_login_failure(login_id: login_id, password: "kindergarten-password")
    end
  end

  test "logs in only with an exact match for a login id containing stored whitespace" do
    @kindergarten_user.update!(login_id: " Sakura ")

    assert_login_failure(login_id: "Sakura", password: "kindergarten-password")

    post kindergarten_login_url, params: { login_id: @kindergarten_user.login_id, password: "kindergarten-password" }

    assert_redirected_to root_url
    assert_equal @kindergarten_user.id, request.session[:user_id]
  end

  test "retains the entered login id but does not render the password after failure" do
    assert_login_failure(login_id: " Sakura ", password: "wrong-password")

    assert_select "input[name=login_id][value=?]", " Sakura "
    assert_select "input[name=password][value]", count: 0
  end

  test "does not carry the login error into the next page request" do
    assert_login_failure(login_id: "unknown", password: "kindergarten-password")

    get kindergarten_login_url

    assert_response :success
    assert_select "[role=alert]", count: 0
  end

  private

  def assert_login_failure(credentials)
    post kindergarten_login_url, params: credentials

    assert_response :unprocessable_content
    assert_nil request.session[:user_id]
    assert_select "[role=alert]", text: "ログインIDまたはパスワードが正しくありません"
    assert_select "form[action=?]", kindergarten_login_path
  end
end

class KindergartenSessionsSessionTest < ActionController::TestCase
  tests KindergartenSessionsController

  test "successful login uses the shared session reset and current user management" do
    user = User.create!(login_id: "Sakura", password: "kindergarten-password",
      role: :kindergarten, kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
    session[:previous_value] = "old-session-data"

    post :create, params: { login_id: user.login_id, password: "kindergarten-password" }

    assert_redirected_to root_url
    assert_equal user.id, session[:user_id]
    assert_nil session[:previous_value]
    assert_equal user, @controller.send(:current_user)
    assert_equal true, @controller.send(:logged_in?)
    assert_equal true, @controller.send(:kindergarten_user?)
  end
end
