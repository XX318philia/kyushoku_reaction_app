class Kindergarten < ApplicationRecord
  has_one :user
  has_many :classrooms

  validates :name, presence: true
end
