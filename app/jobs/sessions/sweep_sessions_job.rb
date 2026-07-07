# frozen_string_literal: true

# Periodically deletes expired sessions. Matches Go's sessionStore
# reaper goroutine that sweeps every 5 minutes (config/initializers
# in Go ran at 5min intervals; we use SolidQueue recurring here).
class Sessions::SweepSessionsJob < ApplicationJob
  queue_as :default

  def perform
    deleted = Session.where("expires_at < ?", Time.current).delete_all
    Rails.logger.info("[sessions] swept #{deleted} expired sessions") if deleted > 0
  end
end
