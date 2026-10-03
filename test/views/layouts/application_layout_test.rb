require "test_helper"

class ApplicationLayoutTest < ActionView::TestCase
  test "a page can omit the header while retaining the shared footer" do
    render inline: "<% content_for :hide_header, true %><main>利用規約</main>", layout: "layouts/application"

    assert_select "header", count: 0
    assert_select "main", text: "利用規約"
    assert_select "footer a[href='#']", text: "利用規約"
    assert_select "footer a[href='#']", text: "プライバシーポリシー"
  end
end
