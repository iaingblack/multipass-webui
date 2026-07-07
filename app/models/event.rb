# frozen_string_literal: true

# Append-only audit log of state-changing operations. Replaces Go's
# events.jsonl file (rotating at 10k lines, in-memory 200-event cache).
# Using a DB table gives us free indexing, query caching, and durability.
class Event < ApplicationRecord
  self.primary_key = :id

  CATEGORIES = %w[vm schedule ansible llm config webhook proxy].freeze
  ACTORS     = %w[user scheduler llm_agent system].freeze
  RESULTS    = %w[success failed partial no_targets].freeze

  validates :category, inclusion: { in: CATEGORIES }
  validates :actor, inclusion: { in: ACTORS }
  validates :result, inclusion: { in: RESULTS }, allow_nil: true

  before_validation :assign_id, on: :create
  after_create :dispatch_webhooks

  # Emit + persist an event. Convenience wrapper matching Go's
  # EventLog.EmitEvent(category, action, actor, resource, result, detail).
  def self.emit!(category:, action:, actor:, resource: nil, result: nil, detail: nil, endpoint: nil, payload: nil)
    return unless CATEGORIES.include?(category)
    create!(
      category:, action:, actor:, resource:, result:,
      detail:, endpoint:, payload:
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[event] failed to emit: #{e.message}")
    nil
  end

  # Emit for an HTTP request — hardcodes actor: "user" and adds endpoint.
  def self.emit_http!(category:, action:, resource:, result:, detail:, request:)
    emit!(
      category:, action:, resource:, result:, detail:,
      actor: "user",
      endpoint: "#{request.method} #{request.path}",
      payload: { params: request.params.except(:controller, :action).to_h }
    )
  end

  private

  # Mirror Go's ID format: <unix_seconds>-<4_hex_bytes>
  def assign_id
    self.id ||= "#{Time.now.to_i}-#{SecureRandom.hex(2)}"
  end

  def dispatch_webhooks
    # Phase 6: WebhookDispatchJob.perform_later(self)
  end
end
