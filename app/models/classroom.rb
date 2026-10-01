class Classroom < ApplicationRecord
  belongs_to :kindergarten

  validates :name, presence: true, uniqueness: { scope: :kindergarten_id }
end
