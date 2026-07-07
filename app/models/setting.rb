# frozen_string_literal: true

# Singleton settings row — the one and only configuration row.
# Use Setting.current to grab it; it's seeded on first access if missing.
#
# Bcrypt hashes are portable between Go and Ruby: Go's bcrypt.GenerateFromPassword
# produces "$2b$..." hashes, and BCrypt::Password.new reads that format.
# A migration from the Go config.json can copy the password_digest verbatim.
class Setting < ApplicationRecord
  has_secure_password

  DEFAULT_USERNAME = "admin"
  DEFAULT_PASSWORD = "admin"  # first-run only; user should change

  validates :username, presence: true,
                       format: { with: /\A[a-zA-Z0-9_-]+\z/, message: "only letters, digits, hyphens, underscores" }

  # Get-or-create the singleton row. First-time callers get the default
  # admin/admin credentials — same as Go's CreateDefault() at
  # internal/config/config.go:716-741.
  def self.current
    first || create!(username: DEFAULT_USERNAME, password: DEFAULT_PASSWORD)
  end

  # Bcrypt migration helper: given a raw "$2b$..." hash from Go's config.json,
  # install it as the password_digest without re-hashing.
  def install_bcrypt_hash!(hash)
    update!(password_digest: hash)
  end
end
