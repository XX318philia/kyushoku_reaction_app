class FeedbackTarget < ApplicationRecord
  belongs_to :dish

  validates :target_date, presence: true, uniqueness: true
end
