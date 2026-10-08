# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_08_044708) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "classrooms", force: :cascade do |t|
    t.bigint "kindergarten_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "kindergarten_id", "name" ], name: "index_classrooms_on_kindergarten_id_and_name", unique: true
    t.index [ "kindergarten_id" ], name: "index_classrooms_on_kindergarten_id"
  end

  create_table "dishes", force: :cascade do |t|
    t.string "name", null: false
    t.integer "category", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "name", "category" ], name: "index_dishes_on_name_and_category", unique: true
  end

  create_table "feedback_targets", force: :cascade do |t|
    t.bigint "dish_id", null: false
    t.date "target_date", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "dish_id" ], name: "index_feedback_targets_on_dish_id"
    t.index [ "target_date" ], name: "index_feedback_targets_on_target_date", unique: true
  end

  create_table "kindergartens", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "reactions", force: :cascade do |t|
    t.bigint "classroom_id", null: false
    t.bigint "feedback_target_id", null: false
    t.integer "positive_count", null: false
    t.integer "neutral_count", null: false
    t.integer "negative_count", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "classroom_id", "feedback_target_id" ], name: "index_reactions_on_classroom_id_and_feedback_target_id", unique: true
    t.index [ "classroom_id" ], name: "index_reactions_on_classroom_id"
    t.index [ "feedback_target_id" ], name: "index_reactions_on_feedback_target_id"
    t.check_constraint "(positive_count + neutral_count + negative_count) > 0", name: "reactions_total_count_positive"
    t.check_constraint "negative_count >= 0", name: "reactions_negative_count_non_negative"
    t.check_constraint "neutral_count >= 0", name: "reactions_neutral_count_non_negative"
    t.check_constraint "positive_count >= 0", name: "reactions_positive_count_non_negative"
  end

  create_table "users", force: :cascade do |t|
    t.string "login_id", null: false
    t.string "password_digest", null: false
    t.string "role", null: false
    t.bigint "kindergarten_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "kindergarten_id" ], name: "index_users_on_kindergarten_id", unique: true
    t.index [ "login_id" ], name: "index_users_on_login_id", unique: true
  end

  add_foreign_key "classrooms", "kindergartens"
  add_foreign_key "feedback_targets", "dishes"
  add_foreign_key "reactions", "classrooms"
  add_foreign_key "reactions", "feedback_targets"
  add_foreign_key "users", "kindergartens"
end
