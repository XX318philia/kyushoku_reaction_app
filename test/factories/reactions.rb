FactoryBot.define do
  factory :reaction do
    association :classroom
    association :feedback_target
    positive_count { 1 }
    neutral_count { 0 }
    negative_count { 0 }
  end
end
