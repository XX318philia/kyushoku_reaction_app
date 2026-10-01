class Kindergarten < ApplicationRecord
  has_many :classrooms

  validates :name, presence: true
end
