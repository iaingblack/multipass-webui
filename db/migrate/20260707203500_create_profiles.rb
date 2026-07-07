# frozen_string_literal: true

# Launch profiles — saved VM configurations for one-click deploy.
# Mirrors Go's Profile struct (internal/config/config.go:46-57).
class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.string :id_slug, null: false  # ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$
      t.string :name, null: false
      t.string :release
      t.integer :cpus
      t.integer :memory_mb
      t.integer :disk_gb
      t.string :cloud_init
      t.string :network
      t.string :playbook
      t.string :group_name
      t.boolean :builtin, default: false

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :profiles, :id_slug, unique: true
  end
end
