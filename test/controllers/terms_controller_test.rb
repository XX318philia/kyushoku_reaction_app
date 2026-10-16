require "test_helper"

class TermsControllerTest < ActionDispatch::IntegrationTest
  test "terms is public with the approved text and only the TOP navigation when logged out" do
    get terms_url

    assert_terms_page
    assert_select ".terms-navigation a", count: 1
    assert_select ".terms-navigation a[href=?]", root_path, text: "TOP"

    get root_path

    assert_response :success
    assert_select "header, footer", count: 2
  end

  test "the approved articles use semantic headings and lists and keep the fixed publication dates" do
    travel_to Time.zone.local(2026, 10, 17) do
      get terms_path

      assert_select ".terms-body > section > h2" do |headings|
        assert_equal [
          "第1条（サービスの目的・位置づけ）", "第2条（アカウントと利用方法）", "第3条（リアクションの記録・集計）",
          "第4条（共有アカウント・共有データ）", "第5条（フィードバック対象料理の設定取消）", "第6条（サービスの制限事項）",
          "第7条（責任の範囲）", "第8条（サービスの停止・終了）", "第9条（利用規約の変更）", "第10条（利用者に関する情報の取扱い）"
        ], headings.map(&:text)
      end
      assert_select ".terms-body > section", count: 10
      assert_select ".terms-body > section > ol", count: 9
      assert_select "#terms-article-3 + ol > li > ul > li", count: 3
      assert_select "#terms-article-5 + ol > li", text:
        "設定を取り消した場合、当日の対象料理の設定情報と、それに紐づくリアクション記録が削除されます。"
      assert_select "#terms-article-7 + ol > li", text:
        "本規約は、運営者が法令に基づいて負う損害賠償責任その他の責任を、一律に免除するものではありません。"
      assert_select "#terms-article-8 + ol > li:first-child", text:
        "運営者は、メンテナンス、障害への対応、運用上の事情などにより、本サービスの全部または一部を停止する場合があります。"
      assert_select "#terms-article-10 + p", count: 1
      assert_select ".terms-body p", text: "制定日：2026年10月16日"
      assert_select ".terms-body p", text: "施行日：2026年10月16日"
      assert_select ".terms-body time[datetime='2026-10-16']", text: "2026年10月16日", count: 2
    end
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
    assert_select ".terms-body > section > h2", count: 10
    assert_select ".terms-body p", text: "開発・運営：Philia"
    assert_select "header, footer", count: 0
    assert_select "head link[href=?]",
      "https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400&display=swap", count: 1
    assert_no_match(/表示状態：|ナビゲーションはログイン状態|優先環境：|優先事項：|概要：|ダミーテキスト|別タスク|【正式公開時に確定】/, response.body)
  end
end
