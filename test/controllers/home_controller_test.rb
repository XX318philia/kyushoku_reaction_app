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

  test "login destinations are displayed without links" do
    get root_url

    assert_select "a", text: /幼稚園様はこちら|給食センター様はこちら/, count: 0
    assert_select "p", text: "幼稚園様はこちら" do
      assert_select "a", count: 0
    end
    assert_select "p", text: "給食センター様はこちら" do
      assert_select "a", count: 0
    end
  end
end
