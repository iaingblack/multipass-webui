# frozen_string_literal: true

# Audit log of state-changing operations. Replaces the Go events.jsonl file.
# Categories: vm|schedule|ansible|llm|config|webhook|proxy
# Actors: user|scheduler|llm_agent|system
# Results: success|failed|partial|no_targets
class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events, id: false do |t|
      # ID format mirrors Go: <unix_seconds>-<4_random_hex_bytes>
      t.string :id, primary_key: true, limit: 32
      t.string :category, null: false
      t.string :action, null: false
      t.string :actor, null: false
      t.string :resource
      t.string :result
      t.text :detail
      t.string :endpoint  # for HTTP events: "POST /vms"
      t.json :payload

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :events, :created_at
    add_index :events, [ :category, :created_at ]
    add_index :events, [ :actor, :created_at ]
    add_index :events, [ :resource, :created_at ]
  end
end
