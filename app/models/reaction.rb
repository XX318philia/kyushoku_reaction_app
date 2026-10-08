class Reaction < ApplicationRecord
  belongs_to :classroom
  belongs_to :feedback_target

  validates :classroom_id, uniqueness: { scope: :feedback_target_id }
  validates :positive_count, :neutral_count, :negative_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # numericalityはfalseを型変換後の0として検証するため、型変換前の値で拒否する。
  validates_each :positive_count, :neutral_count, :negative_count do |record, attribute, _value|
    record.errors.add(attribute, :not_a_number) if record.public_send("#{attribute}_before_type_cast") == false
  end
  validate :at_least_one_reaction

  private

  def at_least_one_reaction
    if positive_count == 0 && neutral_count == 0 && negative_count == 0
      errors.add(:base, "リアクション人数を1人以上入力してください")
    end
  end
end
