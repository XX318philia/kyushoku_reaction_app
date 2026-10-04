class CreateDishes < ActiveRecord::Migration[8.1]
  def change
    create_table :dishes do |t|
      t.string :name, null: false
      t.integer :category, null: false

      t.timestamps
    end

    add_index :dishes, [ :name, :category ], unique: true
  end
end
