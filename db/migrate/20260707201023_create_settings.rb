# frozen_string_literal: true

# Singleton settings table — holds the single shared user account and
# host-level configuration. Mirrors the top-level Config struct fields
# from internal/config/config.go in the Go version.
#
# Bcrypt hashes from the Go version are portable: they're stored as
# "$2b$..." strings and BCrypt::Password in Ruby reads the same format,
# so the migration task can copy hashes directly from config.json.
class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :username, null: false, default: "admin"
      t.string :password_digest, null: false  # bcrypt hash

      # Host-level config
      t.integer :listen_port, default: 3000
      t.string :cloud_init_dir, default: ""
      t.string :cloud_init_repo, default: ""
      t.string :playbooks_dir, default: ""
      t.boolean :trust_proxy, default: false

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end

    # Enforce singleton — only one row ever.
    add_index :settings, :id, unique: true
  end
end
