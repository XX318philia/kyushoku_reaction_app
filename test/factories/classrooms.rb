FactoryBot.define do
  factory :classroom do
    association :kindergarten
    sequence(:name) { |n| "テストクラス#{n}" }
  end
end
