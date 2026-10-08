class FeedbackTarget < ApplicationRecord
  belongs_to :dish
  has_many :reactions

  validates :target_date, presence: true, uniqueness: true
end
