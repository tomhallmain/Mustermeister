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

ActiveRecord::Schema[8.0].define(version: 2025_06_09_182203) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "comments", force: :cascade do |t|
    t.text "content"
    t.bigint "user_id", null: false
    t.bigint "task_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "open"
    t.bigint "project_id"
    t.index ["project_id"], name: "index_comments_on_project_id"
    t.index ["status"], name: "index_comments_on_status"
    t.index ["task_id"], name: "index_comments_on_task_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.datetime "due_date"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_activity_at"
    t.string "default_priority", default: "medium"
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "statuses", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "project_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "name"], name: "index_statuses_on_project_id_and_name", unique: true
    t.index ["project_id"], name: "index_statuses_on_project_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "tags_tasks", id: false, force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "tag_id", null: false
    t.index ["tag_id", "task_id"], name: "index_tags_tasks_on_tag_id_and_task_id"
    t.index ["task_id", "tag_id"], name: "index_tags_tasks_on_task_id_and_tag_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.boolean "completed", default: false
    t.datetime "due_date"
    t.string "priority", default: "medium"
    t.bigint "project_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "completed_at"
    t.integer "completed_by"
    t.boolean "archived", default: false
    t.datetime "archived_at"
    t.integer "archived_by"
    t.bigint "status_id", null: false
    t.index ["archived"], name: "index_tasks_on_archived"
    t.index ["completed", "due_date"], name: "index_tasks_on_completed_and_due_date"
    t.index ["completed_by"], name: "index_tasks_on_completed_by"
    t.index ["project_id", "completed"], name: "index_tasks_on_project_id_and_completed"
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["status_id"], name: "index_tasks_on_status_id"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.boolean "admin", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.string "item_type", null: false
    t.bigint "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.text "object"
    t.text "object_changes"
    t.datetime "created_at"
    t.string "ip"
    t.string "user_agent"
    t.integer "user_id"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
    t.index ["user_id"], name: "index_versions_on_user_id"
  end

  add_foreign_key "comments", "projects"
  add_foreign_key "comments", "tasks"
  add_foreign_key "comments", "users"
  add_foreign_key "projects", "users"
  add_foreign_key "statuses", "projects"
  add_foreign_key "tasks", "projects"
  add_foreign_key "tasks", "statuses"
  add_foreign_key "tasks", "users"
  add_foreign_key "tasks", "users", column: "archived_by"
  add_foreign_key "tasks", "users", column: "completed_by", validate: false
end
