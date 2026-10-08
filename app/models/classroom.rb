class Classroom < ApplicationRecord
  belongs_to :kindergarten
  has_many :reactions

  validates :name, presence: true, uniqueness: { scope: :kindergarten_id }
end
