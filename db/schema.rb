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

ActiveRecord::Schema[8.1].define(version: 2026_07_07_201752) do
  create_table "events", id: { type: :string, limit: 32 }, force: :cascade do |t|
    t.string "action", null: false
    t.string "actor", null: false
    t.string "category", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.text "detail"
    t.string "endpoint"
    t.json "payload"
    t.string "resource"
    t.string "result"
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["actor", "created_at"], name: "index_events_on_actor_and_created_at"
    t.index ["category", "created_at"], name: "index_events_on_category_and_created_at"
    t.index ["created_at"], name: "index_events_on_created_at"
    t.index ["resource", "created_at"], name: "index_events_on_resource_and_created_at"
  end

  create_table "groups", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["name"], name: "index_groups_on_name", unique: true
    t.index ["position"], name: "index_groups_on_position"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.string "token_hash", limit: 64, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "user_agent"
    t.index ["expires_at"], name: "index_sessions_on_expires_at"
    t.index ["token_hash"], name: "index_sessions_on_token_hash", unique: true
  end

  create_table "settings", force: :cascade do |t|
    t.string "cloud_init_dir", default: ""
    t.string "cloud_init_repo", default: ""
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "listen_port", default: 3000
    t.string "password_digest", null: false
    t.string "playbooks_dir", default: ""
    t.boolean "trust_proxy", default: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "username", default: "admin", null: false
    t.index ["id"], name: "index_settings_on_id", unique: true
  end

  create_table "vm_assignments", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "group_id"
    t.boolean "is_template", default: false, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "vm_name", null: false
    t.index ["group_id"], name: "index_vm_assignments_on_group_id"
    t.index ["vm_name"], name: "index_vm_assignments_on_vm_name", unique: true
  end

  create_table "vm_defaults", force: :cascade do |t|
    t.integer "cpus", default: 2, null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "disk_gb", default: 8, null: false
    t.integer "memory_mb", default: 1024, null: false
    t.text "ssh_private_key"
    t.text "ssh_public_key"
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  add_foreign_key "vm_assignments", "groups"
end
