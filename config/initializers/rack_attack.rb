# frozen_string_literal: true

# Rate limiting via rack-attack — replaces Go's two limiters:
#   1. loginRateLimiter (5/min per IP)  — middleware.go:178-251
#   2. apiRateLimiter   (30/min per IP) — middleware.go:254-323
Rack::Attack.cache.store = if ENV["REDIS_URL"]
                             Redis::Store.new(ENV["REDIS_URL"])
                           else
                             ActiveSupport::Cache::MemoryStore.new
                           end

# Login throttle: 5 attempts per minute per IP.
# Matches loginRateLimiter at middleware.go:178-251.
Rack::Attack.throttle("logins/ip", limit: 5, period: 60) do |req|
  next unless req.path == "/login" && req.post?
  req.ip
end

# API throttle: 30 chat/VM-creation requests per minute per IP.
# Matches apiRateLimiter at middleware.go:254-323.
Rack::Attack.throttle("api/ip", limit: 30, period: 60) do |req|
  next unless req.path.match?(%r{\A/(vms|chat)(/|\z)})
  req.ip
end

# Friendly response when throttled.
Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"] || {}
  now = match_data[:epoch_time] || Time.now.to_i
  headers = {
    "Content-Type" => "application/json",
    "RateLimit-Limit" => match_data[:limit].to_s,
    "RateLimit-Remaining" => "0",
    "RateLimit-Reset" => (match_data[:period] - (now % match_data[:period])).to_s
  }
  body = { error: "rate limit exceeded; retry after #{headers["RateLimit-Reset"]}s" }.to_json
  [ 429, headers, [ body ] ]
end
