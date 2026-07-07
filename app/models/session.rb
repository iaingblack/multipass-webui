# frozen_string_literal: true

# A persistent login session — a server-side 256-bit random token, hashed
# at rest with SHA-256 (matches the Go API-token pattern at
# handlers_tokens.go:90-94, applied to sessions here for the same reason:
# a DB compromise can't replay them).
#
# Tokens are issued by SessionsController#create on successful login and
# stored in a signed cookie on the client. ApplicationController#require_login
# looks them up by hash and rejects expired ones.
#
# Reaping: an hourly job (Sessions::SweepSessionsJob) deletes rows whose
# expires_at has passed — matches Go's sessionStore reaper goroutine that
# sweeps every 5 minutes (configurable in config/initializers/sessions.rb).
class Session < ApplicationRecord
  TOKEN_BYTES = 32      # 256-bit random token
  TTL_HOURS   = 24      # matches Go sessionStore ttl at routes.go:53

  # Hash a raw token with SHA-256 for storage. Constant-time comparison
  # isn't needed here (DB index lookup is the gate), but we still hash so
  # the column can't be replayed.
  def self.hash_token(raw)
    Digest::SHA256.hexdigest(raw)
  end

  # Issue a new session for the given IP/UA. Returns the raw token — the
  # only time the caller sees it; the DB stores only the hash.
  def self.issue!(ip_address: nil, user_agent: nil)
    raw = SecureRandom.hex(TOKEN_BYTES)
    create!(
      token_hash: hash_token(raw),
      expires_at: TTL_HOURS.hours.from_now,
      ip_address:,
      user_agent:
    )
    raw
  end

  # Look up by raw token. Returns the session if valid+unexpired, else nil.
  # Reaps the row if expired so the next sweep has less work.
  def self.find_valid(raw_token)
    return nil if raw_token.blank?
    session = find_by(token_hash: hash_token(raw_token))
    return nil unless session
    return session.reap! unless session.expires_at.future?
    session
  end

  # Delete self if expired.
  def reap!
    destroy unless expires_at.future?
    nil
  end
end
