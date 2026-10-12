require "test_helper"

class TermsControllerTest < ActionDispatch::IntegrationTest
  test "terms is public with dummy text and only the TOP navigation when logged out" do
    get terms_url

    assert_terms_page
    assert_select ".terms-navigation a", count: 1
    assert_select ".terms-navigation a[href=?]", root_path, text: "TOP"

    get root_path

    assert_response :success
    assert_select "header, footer", count: 2
  end

  test "direct access shows kindergarten navigation and each destination opens" do
    user = User.create!(login_id: "TermsKindergarten", password: "terms-password", role: :kindergarten,
      kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
    post kindergarten_login_path, params: { login_id: user.login_id, password: "terms-password" }

    { "入力・編集" => new_reaction_path, "集計結果" => reactions_path }.each do |label, path|
      get terms_path

      assert_terms_page
      assert_select ".terms-navigation--kindergarten a", count: 2
      assert_select ".terms-navigation a[href=?]", path, text: label
      assert_select ".terms-navigation a", text: "TOP", count: 0

      get path

      assert_response :success
      assert_select "header, footer", count: 2
    end
  end

  test "direct access shows center navigation and each destination opens" do
    user = User.create!(login_id: "TermsCenter", password: "terms-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "terms-password" }

    { "集計結果" => center_reaction_results_path, "対象料理設定" => new_feedback_target_path,
      "料理マスタ登録" => new_dish_path }.each do |label, path|
      get terms_path

      assert_terms_page
      assert_select ".terms-navigation--center a", count: 3
      assert_select ".terms-navigation a[href=?]", path, text: label
      assert_select ".terms-navigation a", text: "TOP", count: 0

      get path

      assert_response :success
      assert_select "header, footer", count: 2
    end
  end

  private

  def assert_terms_page
    assert_response :success
    assert_select "title", text: "利用規約 | 給食リアクション"
    assert_select "main h1", text: "利用規約", count: 1
    assert_select ".terms-body p", text: "本文領域（ダミーテキスト）"
    assert_select ".terms-body p", text: "利用規約の本文は別タスクで作成します。"
    assert_select "header, footer", count: 0
    assert_select "head link[href=?]",
      "https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400&display=swap", count: 1
    assert_no_match(/表示状態：|ナビゲーションはログイン状態|優先環境：|優先事項：/, response.body)
  end
end
