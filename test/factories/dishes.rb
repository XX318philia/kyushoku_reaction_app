FactoryBot.define do
  factory :dish do
    # 料理名に算用数字を使えないため、連番を使用可能な漢字に変換する。
    sequence(:name) { |n| "テスト料理#{n.to_s.tr("0123456789", "零一二三四五六七八九")}" }
    category { :main_dish }
  end
end
