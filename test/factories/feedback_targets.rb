FactoryBot.define do
  factory :feedback_target do
    association :dish
    sequence(:target_date) { |n| Date.new(2000, 1, 1) + n - 1 }
  end
end
