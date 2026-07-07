#!/usr/bin/env ruby
# frozen_string_literal: true

# Spike verifier: opens a real WebSocket to the running Rails /cable
# endpoint, subscribes to TerminalChannel, sends a keystroke, and prints
# the response. Exits 0 on success, non-zero on failure.
#
# Run with:  bin/rails runner script/verify_terminal_spike.rb
#
# Prereqs:
#   - Rails server on http://localhost:3000  (bin/rails server --daemon)
#   - VM named by ENV SPIKE_VM (default "rootplane-hello-01") must be Running

require "websocket/driver"
require "socket"
require "net/http"
require "json"
require "base64"
require "uri"

VM_NAME = ENV.fetch("SPIKE_VM", "rootplane-hello-01")

# --- Step 1: create a session via HTTP -------------------------------
puts "→ POST /spike/terminals vm_name=#{VM_NAME.inspect}"
uri = URI("http://localhost:3000/spike/terminals")
res = Net::HTTP.post_form(uri, vm_name: VM_NAME)
unless res.code.to_i.between?(300, 399)
  abort "  session creation failed: HTTP #{res.code} #{res.message}"
end
loc = res["Location"]
session_id = URI(loc).query.split("&").map { |kv| kv.split("=") }.to_h.fetch("session_id")
puts "  session_id: #{session_id}"

# --- Step 2: open WebSocket to /cable --------------------------------
puts "→ WebSocket connect ws://localhost:3000/cable"

# Tiny client wrapper so websocket/driver can write to a real socket.
class WSClient
  attr_reader :driver, :url

  def initialize(url)
    @url = url
    @uri = URI(url)
    @socket = TCPSocket.new(@uri.host, @uri.port || 80)
    @driver = WebSocket::Driver.client(self)
    @inbox = Queue.new
    @closed = false
  end

  def start
    @driver.on(:message) { |e| @inbox << e.data }
    @driver.on(:close)   { @closed = true; @inbox << nil }
    @driver.start

    # Reader thread: feed bytes from the socket into the driver
    Thread.new do
      until @closed
        begin
          chunk = @socket.read_nonblock(4096)
          @driver.parse(chunk)
        rescue IO::WaitReadable
          IO.select([@socket], nil, nil, 0.1)
        rescue EOFError, SystemCallError
          @closed = true
          @inbox << nil
          break
        end
      end
    end
  end

  def write(data)
    @socket.write(data)
  end

  def send_json(obj)
    @driver.text(obj.to_json)
  end

  def next_message(timeout: 5)
    @inbox.pop(true) # non-blocking
  rescue ThreadError
    # queue empty; wait briefly
    Thread.pass
    sleep 0.05
    retry if timeout > 0
    nil
  end

  def wait_for_message(timeout: 5)
    deadline = Time.now + timeout
    loop do
      msg = begin
              @inbox.pop(true)
            rescue ThreadError
              nil
            end
      return msg unless msg.nil?
      return nil if Time.now >= deadline
      sleep 0.05
    end
  end
end

client = WSClient.new("ws://localhost:3000/cable")
client.start

# ActionCable handshake: wait for the welcome message
welcome = client.wait_for_message(timeout: 5)
abort "no welcome received" unless welcome
puts "  welcome: #{welcome}"

# --- Step 3: subscribe to TerminalChannel ----------------------------
puts "→ Subscribe to TerminalChannel vm_name=#{VM_NAME} session_id=#{session_id}"
client.send_json({
  command: "subscribe",
  identifier: { channel: "TerminalChannel", vm_name: VM_NAME, session_id: session_id }.to_json
})

# Expect: confirmation + scrollback transmit
confirm = client.wait_for_message(timeout: 5)
abort "no subscribe confirmation" unless confirm
puts "  subscribed: #{confirm[0..120]}..."

# Wait for scrollback (may be empty if VM just started)
scrollback = client.wait_for_message(timeout: 3)
if scrollback
  data = JSON.parse(scrollback) rescue nil
  if data && data["type"] == "scrollback"
    bytes = Base64.strict_decode64(data["data"])
    puts "  scrollback: #{bytes.bytesize} bytes received"
  end
end

# --- Step 4: send a keystroke and look for output -------------------
puts "→ Send 'echo spike_test_42\\n' to PTY"
input = "echo spike_test_42\n"
encoded = Base64.strict_encode64(input)
client.send_json({
  command: "message",
  identifier: { channel: "TerminalChannel", vm_name: VM_NAME, session_id: session_id }.to_json,
  data: { data: encoded }.to_json
})

# Wait for output containing our marker
puts "→ Waiting for 'spike_test_42' in output..."
deadline = Time.now + 10
got_marker = false
while Time.now < deadline
  msg = client.wait_for_message(timeout: 2)
  break if msg.nil?
  data = JSON.parse(msg) rescue next
  # ActionCable wraps channel broadcasts as { identifier:, message: { ... } }
  payload = data["message"] || data
  next unless payload["type"] == "output"
  decoded = Base64.strict_decode64(payload["data"]) rescue ""
  print decoded
  if decoded.include?("spike_test_42")
    got_marker = true
    break
  end
end

puts
if got_marker
  puts "✓ SPIKE PASSED: PTY round-trip works over ActionCable"
  exit 0
else
  puts "✗ SPIKE FAILED: did not see marker in output within timeout"
  exit 1
end
