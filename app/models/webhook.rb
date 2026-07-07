# frozen_string_literal: true

class Webhook < ApplicationRecord
  self.primary_key = :id_slug

  CATEGORIES = %w[vm schedule ansible llm config webhook proxy].freeze
  RESULTS    = %w[success failed partial no_targets].freeze

  validates :id_slug, presence: true, uniqueness: true
  validates :name, presence: true
  validates :url, presence: true,
                  format: { with: %r{\Ahttps?://}, message: "must be http(s)://" }
  validate :categories_subset?
  validate :results_subset?

  # Dispatch an event to this webhook via HTTP POST. Runs in a background
  # job in production; this method is the synchronous core.
  def deliver(event)
    payload = { event: event.attributes, webhook: { id: id_slug, name: name } }.to_json
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 10
    http.open_timeout = 5

    req = Net::HTTP::Post.new(uri.request_uri)
    req["Content-Type"] = "application/json"
    req["User-Agent"] = "Multipass-WebUI/1.0"
    req["X-PassGo-Signature"] = hmac_signature(payload) if secret.present?
    req.body = payload

    response = http.request(req)
    (200..299).cover?(response.code.to_i) ? :success : :failed
  rescue StandardError => e
    Rails.logger.warn("[webhook] delivery to #{url} failed: #{e.message}")
    :failed
  end

  # Loop prevention: events with category="webhook" never trigger
  # further webhooks. Matches Go webhooks.go:33-35.
  def self.should_dispatch?(event, webhook)
    return false if event.category == "webhook"
    return false unless webhook.enabled
    return true if webhook.categories.blank?
    webhook.categories.include?(event.category)
  end

  private

  def hmac_signature(body)
    hmac = OpenSSL::HMAC.hexdigest("SHA256", secret, body)
    # NOT GitHub's "sha256=<hex>" format — raw hex (matches Go webhooks.go:96).
    hmac
  end

  def categories_subset?
    return unless categories.is_a?(Array)
    bad = categories - CATEGORIES
    errors.add(:categories, "unknown: #{bad.inspect}") if bad.any?
  end

  def results_subset?
    return unless results.is_a?(Array)
    bad = results - RESULTS
    errors.add(:results, "unknown: #{bad.inspect}") if bad.any?
  end
end
