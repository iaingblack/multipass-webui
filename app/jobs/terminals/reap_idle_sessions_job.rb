# frozen_string_literal: true

# Reaps idle terminal sessions. Matches Go's pty_store.go:248-279 reaper:
# ticks every 1 minute, kills sessions with no subscribers AND last_active
# older than 30 minutes. The "no subscribers" check is implicit — if a
# session has no ActionCable subscribers, no one is reading its output,
# so it's safe to kill.
#
# SolidQueue recurring schedule in config/recurring.yml runs this every minute.
class Terminals::ReapIdleSessionsJob < ApplicationJob
  queue_as :default

  IDLE_TTL = 30.minutes

  def perform
    reaped = []
    Terminals::Session::SESSIONS.each do |id, sess|
      next if sess.created_at > IDLE_TTL.ago
      # Check ActionCable subscriber count for this session's output stream.
      # If 0, no one is listening — safe to kill.
      conn_count = ActionCable.server.pubsub.send(:adapter).instance_variable_get(:@subscriber_counts)&.dig("terminal:#{id}:output") rescue 0
      next if conn_count.to_i > 0
      sess.kill
      reaped << id
    end
    Rails.logger.info("[terminals] reaped #{reaped.length} idle sessions: #{reaped.inspect}") if reaped.any?
  end
end
