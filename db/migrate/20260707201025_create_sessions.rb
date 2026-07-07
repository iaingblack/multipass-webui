# frozen_string_literal: true

# Persistent login sessions — server-side session tokens with 24h TTL.
# Matches Go's sessionStore (in-memory map token→expiry, reaped every 5min).
# Storing in DB makes them survive Puma restarts (improvement over Go).
#
# Token is a 32-byte hex (256-bit) random string, generated server-side,
# never reused. We store only a SHA-256 hash so a DB leak can't be replayed
# (matches the Go handler_tokens.go API-token pattern, but for sessions).
class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      # SHA-256 hex of the random token issued to the client. 64 hex chars.
      t.string :token_hash, null: false, limit: 64
      t.datetime :expires_at, null: false
      t.string :ip_address   # best-effort capture for audit
      t.string :user_agent

      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :sessions, :token_hash, unique: true
    add_index :sessions, :expires_at  # cheap reaping of expired rows
  end
end
