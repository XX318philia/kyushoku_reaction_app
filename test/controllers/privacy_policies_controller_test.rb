require "test_helper"

class PrivacyPoliciesControllerTest < ActionDispatch::IntegrationTest
  test "privacy policy is public with dummy text and only the TOP navigation when logged out" do
    get privacy_policy_url

    assert_privacy_policy_page
    assert_select ".privacy-policy-navigation a", count: 1
    assert_select ".privacy-policy-navigation a[href=?]", root_path, text: "TOP"

    get root_path

    assert_response :success
    assert_select "header, footer", count: 2
  end

  test "direct access shows kindergarten navigation and each destination opens" do
    user = User.create!(login_id: "PrivacyKindergarten", password: "privacy-password", role: :kindergarten,
      kindergarten: Kindergarten.create!(name: "さくら幼稚園"))
    post kindergarten_login_path, params: { login_id: user.login_id, password: "privacy-password" }

    { "入力・編集" => new_reaction_path, "集計結果" => reactions_path }.each do |label, path|
      get privacy_policy_path

      assert_privacy_policy_page
      assert_select ".privacy-policy-navigation--kindergarten a", count: 2
      assert_select ".privacy-policy-navigation a[href=?]", path, text: label
      assert_select ".privacy-policy-navigation a", text: "TOP", count: 0

      get path

      assert_response :success
      assert_select "header, footer", count: 2
    end
  end

  test "direct access shows center navigation and each destination opens" do
    user = User.create!(login_id: "PrivacyCenter", password: "privacy-password", role: :center)
    post center_login_path, params: { login_id: user.login_id, password: "privacy-password" }

    { "集計結果" => center_reaction_results_path, "対象料理設定" => new_feedback_target_path,
      "料理マスタ登録" => new_dish_path }.each do |label, path|
      get privacy_policy_path

      assert_privacy_policy_page
      assert_select ".privacy-policy-navigation--center a", count: 3
      assert_select ".privacy-policy-navigation a[href=?]", path, text: label
      assert_select ".privacy-policy-navigation a", text: "TOP", count: 0

      get path

      assert_response :success
      assert_select "header, footer", count: 2
    end
  end

  private

  def assert_privacy_policy_page
    assert_response :success
    assert_select "title", text: "プライバシーポリシー | 給食リアクション"
    assert_select "main h1", text: "プライバシーポリシー", count: 1
    assert_select ".privacy-policy-body p", count: 2
    assert_select ".privacy-policy-body p", text: "本文領域（ダミーテキスト）"
    assert_select ".privacy-policy-body p", text: "プライバシーポリシーの本文は別タスクで作成します。"
    assert_select "header, footer", count: 0
    assert_select "head link[href=?]",
      "https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400&display=swap", count: 1
    assert_no_match(/表示状態：|ナビゲーションはログイン状態|URLを直接入力|MVPはダミー本文|横スクロールなし|優先環境：|優先事項：/, response.body)
  end
end
