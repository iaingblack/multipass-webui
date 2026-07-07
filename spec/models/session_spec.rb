# frozen_string_literal: true

require "rails_helper"

RSpec.describe Session, type: :model do
  describe ".hash_token" do
    it "returns a 64-char SHA-256 hex of the input" do
      hash = described_class.hash_token("abc")
      expect(hash).to eq(Digest::SHA256.hexdigest("abc"))
      expect(hash.length).to eq(64)
    end

    it "returns the same hash for the same input (deterministic)" do
      expect(described_class.hash_token("xyz"))
        .to eq(described_class.hash_token("xyz"))
    end
  end

  describe ".issue!" do
    it "persists a hashed token + 24h expiry" do
      raw = described_class.issue!(ip_address: "1.2.3.4", user_agent: "test")
      expect(raw.length).to eq(64) # 32 bytes hex
      record = described_class.find_by(token_hash: described_class.hash_token(raw))
      expect(record).not_to be_nil
      expect(record.expires_at).to be > 23.hours.from_now
      expect(record.ip_address).to eq("1.2.3.4")
    end

    it "never persists the raw token" do
      raw = described_class.issue!
      described_class.all.each do |s|
        expect(s.token_hash).not_to eq(raw)
      end
    end
  end

  describe ".find_valid" do
    it "returns the session for a valid raw token" do
      raw = described_class.issue!
      expect(described_class.find_valid(raw)).to be_a(described_class)
    end

    it "returns nil for a bogus token" do
      expect(described_class.find_valid("not-real")).to be_nil
    end

    it "returns nil for a blank token" do
      expect(described_class.find_valid("")).to be_nil
      expect(described_class.find_valid(nil)).to be_nil
    end

    it "reaps + returns nil for an expired session" do
      raw = described_class.issue!
      described_class.last.update!(expires_at: 1.hour.ago)
      expect(described_class.find_valid(raw)).to be_nil
      expect(described_class.exists?).to be(false)
    end
  end
end
