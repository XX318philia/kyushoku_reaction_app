class CreateReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :reactions do |t|
      t.references :classroom, null: false, foreign_key: true
      t.references :feedback_target, null: false, foreign_key: true
      t.integer :positive_count, null: false
      t.integer :neutral_count, null: false
      t.integer :negative_count, null: false

      t.timestamps

      t.check_constraint "positive_count >= 0", name: "reactions_positive_count_non_negative"
      t.check_constraint "neutral_count >= 0", name: "reactions_neutral_count_non_negative"
      t.check_constraint "negative_count >= 0", name: "reactions_negative_count_non_negative"
      t.check_constraint "positive_count + neutral_count + negative_count > 0", name: "reactions_total_count_positive"
    end

    add_index :reactions, [ :classroom_id, :feedback_target_id ], unique: true
  end
end
