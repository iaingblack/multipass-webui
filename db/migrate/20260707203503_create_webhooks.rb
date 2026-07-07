# frozen_string_literal: true

# Webhooks — HTTP POST notifications fired on event matches.
# Mirrors Go's Webhook struct (internal/config/config.go:157-166).
class CreateWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :webhooks do |t|
      t.string :id_slug, null: false
      t.string :name, null: false
      t.string :url, null: false
      t.boolean :enabled, default: true
      t.json :categories   # vm|schedule|ansible|llm|config|webhook|proxy
      t.json :results      # success|failed|partial|no_targets
      t.string :secret     # HMAC-SHA256 signing key (nil for export)

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :webhooks, :id_slug, unique: true
  end
end
