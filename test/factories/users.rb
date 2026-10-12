FactoryBot.define do
  factory :user do
    sequence(:login_id) { |n| "factory_user_#{n}" }
    password { "password" }
    role { :kindergarten }
    association :kindergarten

    trait :center do
      role { :center }
      kindergarten { nil }
    end
  end
end
