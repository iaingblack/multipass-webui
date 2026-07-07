# frozen_string_literal: true

class ApiToken < ApplicationRecord
  self.primary_key = :id_slug

  # Token format: pgo_ + 32 hex bytes (matches Go handlers_tokens.go:90).
  TOKEN_PREFIX = "pgo_"
  TOKEN_BYTES = 32

  validates :id_slug, presence: true, uniqueness: true
  validates :name, presence: true, uniqueness: true, length: { maximum: 64 }
  validates :prefix, presence: true
  validates :sha256_digest, presence: true, uniqueness: true

  # Generate a new raw token + persist its hash. Returns the raw token —
  # the only time the caller will see it.
  def self.issue!(name:)
    raise ActiveRecord::RecordInvalid, "name is required" if name.blank?

    id_slug = "tok_#{SecureRandom.hex(8)}"
    raw_token = TOKEN_PREFIX + SecureRandom.hex(TOKEN_BYTES)
    create!(
      id_slug: id_slug,
      name:,
      prefix: raw_token[0, 12],
      sha256_digest: Digest::SHA256.hexdigest(raw_token)
    )
    raw_token
  end

  # Look up by raw token. Constant-time compare against stored hashes.
  def self.find_by_raw_token(raw_token)
    return nil if raw_token.blank?
    return nil unless raw_token.start_with?(TOKEN_PREFIX)

    computed_hash = Digest::SHA256.hexdigest(raw_token)
    find_each do |t|
      return t if OpenSSL.fixed_length_secure_compare(t.sha256_digest, computed_hash)
    rescue ArgumentError
      next
    end
    nil
  end
end
