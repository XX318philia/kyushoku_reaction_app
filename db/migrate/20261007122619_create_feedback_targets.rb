class CreateFeedbackTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :feedback_targets do |t|
      t.references :dish, null: false, foreign_key: true
      t.date :target_date, null: false

      t.timestamps
    end

    add_index :feedback_targets, :target_date, unique: true
  end
end
