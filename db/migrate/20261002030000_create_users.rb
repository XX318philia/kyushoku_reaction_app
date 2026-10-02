class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :login_id, null: false
      t.string :password_digest, null: false
      t.string :role, null: false
      t.references :kindergarten, null: true, foreign_key: true, index: { unique: true }

      t.timestamps
    end

    add_index :users, :login_id, unique: true
  end
end
