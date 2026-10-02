class CreateClassrooms < ActiveRecord::Migration[8.1]
  def change
    create_table :classrooms do |t|
      t.references :kindergarten, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    add_index :classrooms, [ :kindergarten_id, :name ], unique: true
  end
end
