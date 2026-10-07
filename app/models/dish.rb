class Dish < ApplicationRecord
  has_many :feedback_targets

  enum :category, { main_dish: 0, side_dish: 1, soup: 2, fruit_or_dessert: 3 }, validate: true

  before_validation :remove_spaces_from_name

  validates :name, presence: true, uniqueness: { scope: :category }
  # Loに限定して繰り返し記号・部首記号・数字を除き、「ー」「・」は明示的に許可する。
  validates :name, format: { with: /\A(?:[\p{Hiragana}\p{Katakana}\p{Han}&&\p{Lo}]|[ー・])+\z/ }, allow_blank: true
  validates :category, presence: true

  private

  def remove_spaces_from_name
    self.name = name&.delete(" 　")
  end
end
