require "test_helper"

class PrivacyPoliciesControllerTest < ActionDispatch::IntegrationTest
  test "privacy policy is public with the approved text and only the TOP navigation when logged out" do
    get privacy_policy_url

    assert_privacy_policy_page
    assert_select ".privacy-policy-navigation a", count: 1
    assert_select ".privacy-policy-navigation a[href=?]", root_path, text: "TOP"

    get root_path

    assert_response :success
    assert_select "header, footer", count: 2
  end

  test "the manuscript uses semantic articles and lists and keeps the approved article eight and fixed dates" do
    travel_to Time.zone.local(2026, 10, 17) do
      get privacy_policy_path

      assert_select ".privacy-policy-body > section > h2" do |headings|
        assert_equal [
          "第1条（基本方針）", "第2条（取り扱う情報）", "第3条（情報の利用目的）", "第4条（Cookieの利用）",
          "第5条（外部サービスの利用）", "第6条（登録情報の共有）", "第7条（情報の保存・削除）",
          "第8条（開示等の請求・問い合わせ）", "第9条（プライバシーポリシーの変更）"
        ], headings.map(&:text)
      end
      assert_select ".privacy-policy-body > section", count: 9
      assert_select "#privacy-policy-article-2 ~ h3", count: 3
      assert_select "#privacy-policy-article-2 ~ ul > li > ul > li", count: 3
      assert_select "#privacy-policy-article-3 ~ ol > li", count: 6
      assert_select "#privacy-policy-article-5 ~ h3" do |headings|
        assert_equal [ "1. Render", "2. Neon", "3. Google Fonts", "4. UptimeRobot" ], headings.map(&:text)
      end
      assert_select "#privacy-policy-article-7 ~ ul > li", count: 2
      assert_select "#privacy-policy-article-7 ~ p", text:
        "この保持期間はRenderのログに関するものであり、Neonに保存されるデータベース本体や、その復元履歴・バックアップの保存期間とは異なります。"
      assert_select "#privacy-policy-article-8 ~ p" do |paragraphs|
        assert_equal [
          "本サービスにおける個人情報保護法の適用関係、保有個人データの有無、および法令上必要な開示・訂正・利用停止・削除等の請求への対応方法について、確認が必要です。",
          "開発方針として、現時点では問い合わせ先を公開せず、問い合わせフォームも実装しません。",
          "ただし、この方針が法令上必要な情報提供・請求受付の義務を満たすかについては、確認を終えていません。"
        ], paragraphs.map(&:text)
      end
      assert_select ".privacy-policy-body p", text: "制定日：2026年10月16日"
      assert_select ".privacy-policy-body p", text: "施行日：2026年10月16日"
      assert_select ".privacy-policy-body time[datetime='2026-10-16']", text: "2026年10月16日", count: 2
    end
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
    assert_select ".privacy-policy-body > section > h2", count: 9
    assert_select ".privacy-policy-body p", text: "開発・運営：Philia"
    assert_select "header, footer", count: 0
    assert_select "head link[href=?]",
      "https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400&display=swap", count: 1
    assert_no_match(/表示状態：|ナビゲーションはログイン状態|URLを直接入力|ダミーテキスト|別タスク|横スクロールなし|優先環境：|優先事項：|概要：|【公開前要確認】|【正式公開時に確定】/, response.body)
  end
end
