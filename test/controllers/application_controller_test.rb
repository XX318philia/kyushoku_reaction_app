require "test_helper"

class ApplicationControllerTest < ActionController::TestCase
  setup do
    @kindergarten_user = User.create!(login_id: "Sakura", password: "kindergarten-password",
      role: :kindergarten, kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
    @center_user = User.create!(login_id: "Center", password: "center-password", role: :center)
  end

  test "authenticates both roles with the correct login id and password" do
    [ [ @kindergarten_user, "kindergarten-password" ], [ @center_user, "center-password" ] ].each do |user, password|
      assert_equal user, @controller.send(:authenticate_user, login_id: user.login_id, password: password)
    end

    assert_nil session[:user_id]
  end

  test "does not authenticate an unknown login id" do
    assert_nil @controller.send(:authenticate_user, login_id: "unknown", password: "center-password")
    assert_nil session[:user_id]
  end

  test "does not authenticate an incorrect password" do
    assert_nil @controller.send(:authenticate_user, login_id: @center_user.login_id, password: "wrong-password")
    assert_nil session[:user_id]
  end

  test "does not authenticate when login id case differs" do
    [ "center", "CENTER" ].each do |login_id|
      assert_nil @controller.send(:authenticate_user, login_id: login_id, password: "center-password")
    end
  end

  test "does not authenticate when whitespace is added to the login id" do
    [ " Center", "Center ", " Center ", "\tCenter\n", "　Center　" ].each do |login_id|
      assert_nil @controller.send(:authenticate_user, login_id: login_id, password: "center-password")
    end
  end

  test "authenticates a login id containing stored whitespace only when it matches exactly" do
    @center_user.update!(login_id: " Center ")

    assert_equal @center_user, @controller.send(:authenticate_user, login_id: " Center ", password: "center-password")
    assert_nil @controller.send(:authenticate_user, login_id: "Center", password: "center-password")
  end

  test "does not authenticate missing or empty credentials" do
    [ nil, "" ].each do |value|
      assert_nil @controller.send(:authenticate_user, login_id: value, password: "center-password")
      assert_nil @controller.send(:authenticate_user, login_id: @center_user.login_id, password: value)
    end
  end

  test "stores the authenticated user id after resetting the session" do
    session[:previous_value] = "old-session-data"
    user = @controller.send(:authenticate_user, login_id: @center_user.login_id, password: "center-password")

    @controller.send(:log_in, user)

    assert_equal @center_user.id, session[:user_id]
    assert_nil session[:previous_value]
    assert_equal @center_user, @controller.send(:current_user)
    assert_equal true, @controller.send(:logged_in?)
  end

  test "loads the current user from the session user id" do
    session[:user_id] = @kindergarten_user.id

    assert_equal @kindergarten_user, @controller.send(:current_user)
    assert_equal true, @controller.send(:logged_in?)
  end

  test "is logged out without a session user id" do
    assert_nil @controller.send(:current_user)
    assert_equal false, @controller.send(:logged_in?)
    assert_equal false, @controller.send(:kindergarten_user?)
    assert_equal false, @controller.send(:center_user?)
  end

  test "is logged out when the session user no longer exists" do
    session[:user_id] = @center_user.id
    @center_user.destroy!

    assert_nil @controller.send(:current_user)
    assert_equal false, @controller.send(:logged_in?)
    assert_equal false, @controller.send(:kindergarten_user?)
    assert_equal false, @controller.send(:center_user?)
  end

  test "identifies the kindergarten role using the current user" do
    session[:user_id] = @kindergarten_user.id

    assert_equal true, @controller.send(:kindergarten_user?)
    assert_equal false, @controller.send(:center_user?)
  end

  test "identifies the center role using the current user" do
    session[:user_id] = @center_user.id

    assert_equal false, @controller.send(:kindergarten_user?)
    assert_equal true, @controller.send(:center_user?)
  end

  test "updates the current user after an earlier lookup in the same request" do
    session[:user_id] = @kindergarten_user.id
    assert_equal @kindergarten_user, @controller.send(:current_user)

    @controller.send(:log_in, @center_user)

    assert_equal @center_user.id, session[:user_id]
    assert_equal @center_user, @controller.send(:current_user)
    assert_equal false, @controller.send(:kindergarten_user?)
    assert_equal true, @controller.send(:center_user?)
  end

  test "updates the login state after an earlier logged out lookup" do
    assert_equal false, @controller.send(:logged_in?)

    @controller.send(:log_in, @kindergarten_user)

    assert_equal @kindergarten_user, @controller.send(:current_user)
    assert_equal true, @controller.send(:logged_in?)
    assert_equal true, @controller.send(:kindergarten_user?)
  end

  test "exposes the current user login state and role checks to views" do
    session[:user_id] = @kindergarten_user.id
    view = @controller.view_context

    assert_equal @kindergarten_user, view.current_user
    assert_equal true, view.logged_in?
    assert_equal true, view.kindergarten_user?
    assert_equal false, view.center_user?
  end
end
