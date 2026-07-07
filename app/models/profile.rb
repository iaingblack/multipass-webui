# frozen_string_literal: true

class Profile < ApplicationRecord
  self.primary_key = :id_slug

  validates :id_slug, presence: true, uniqueness: true,
                      format: { with: /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}\z/ }
  validates :name, presence: true
  validates :cpus, numericality: { greater_than_or_equal_to: 1 }, allow_nil: true
  validates :memory_mb, numericality: { greater_than_or_equal_to: 512 }, allow_nil: true
  validates :disk_gb, numericality: { greater_than_or_equal_to: 1 }, allow_nil: true

  # Built-in profile (matches Go's agentReadyProfile at config.go:59-68).
  AGENT_READY = {
    id_slug: "agent-ready",
    name: "Agent Ready (VNC + Docker)",
    release: "24.04",
    cpus: 2,
    memory_mb: 4096,
    disk_gb: 20,
    cloud_init: "builtin:agent-ready.yml",
    group_name: "agents",
    builtin: true
  }.freeze

  def self.ensure_builtin!
    find_by(id_slug: AGENT_READY[:id_slug]) ||
      create!(AGENT_READY)
  end
end
