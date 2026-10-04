class Dish < ApplicationRecord
  enum :category, { main_dish: 0, side_dish: 1, soup: 2, fruit_or_dessert: 3 }, validate: true

  before_validation :remove_spaces_from_name

  validates :name, presence: true, uniqueness: { scope: :category }
  validates :name, format: { with: /\A[\p{Hiragana}\p{Katakana}\p{Han}ー・]+\z/ }, allow_blank: true
  validates :category, presence: true

  private

  def remove_spaces_from_name
    self.name = name&.delete(" 　")
  end
end
