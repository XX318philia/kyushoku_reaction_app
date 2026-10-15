require "test_helper"

class ApplicationLayoutTest < ActionView::TestCase
  test "a page can omit the header while retaining the shared footer" do
    render inline: "<% content_for :hide_header, true %><main>利用規約</main>", layout: "layouts/application"

    assert_select "header", count: 0
    assert_select "main", text: "利用規約"
    assert_select "footer a[href=?]", terms_path, text: "利用規約"
    assert_select "footer a[href=?]", privacy_policy_path, text: "プライバシーポリシー"
  end

  test "a page can omit the footer while retaining the shared header" do
    view.define_singleton_method(:logged_in?) { false }
    render inline: "<% content_for :hide_footer, true %><main>本文</main>", layout: "layouts/application"

    assert_select "header .shared-logo[aria-label=?]", "給食リアクション", count: 1
    assert_select "main", text: "本文"
    assert_select "footer", count: 0
  end

  test "a page can omit both the shared header and footer" do
    render inline: "<% content_for :hide_header, true %><% content_for :hide_footer, true %><main>本文</main>", layout: "layouts/application"

    assert_select "header, footer", count: 0
    assert_select "main", text: "本文"
  end
end
