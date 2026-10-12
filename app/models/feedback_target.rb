class FeedbackTarget < ApplicationRecord
  belongs_to :dish
  has_many :reactions, dependent: :destroy

  validates :target_date, presence: true, uniqueness: true

  def reaction_summary
    table = Reaction.arel_table
    positive_count, neutral_count, negative_count = reactions.pick(
      table[:positive_count].sum,
      table[:neutral_count].sum,
      table[:negative_count].sum
    ).map(&:to_i)
    total_count = positive_count + neutral_count + negative_count

    {
      positive_count: positive_count,
      neutral_count: neutral_count,
      negative_count: negative_count,
      total_count: total_count,
      positive_percentage: (positive_count.fdiv(total_count) * 100 if total_count.positive?),
      neutral_percentage: (neutral_count.fdiv(total_count) * 100 if total_count.positive?),
      negative_percentage: (negative_count.fdiv(total_count) * 100 if total_count.positive?)
    }
  end
end
