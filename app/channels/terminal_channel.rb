# frozen_string_literal: true

# Spike channel: subscribes the browser to a PTY session's output stream
# and forwards user input/resize events into the PTY.
#
# Layout (per session):
#   Browser  ─ActionCable─▶  TerminalChannel  ─▶  Terminals::Session (in-process PTY)
#   Session  ─broadcast───▶  TerminalChannel  ─▶  Browser (base64 over JSON)
#
# The 5-byte resize prefix protocol matches the Go implementation
# (handlers_shell.go:77-83): the JS client sends a binary message with
# 0x01 + cols(BE u16) + rows(BE u16); Session#write detects the prefix
# and applies via winsize instead of forwarding to the PTY.
class TerminalChannel < ApplicationCable::Channel
  def subscribed
    @vm_name = params[:vm_name]
    @session_id = params[:session_id]

    unless @vm_name && @session_id
      reject
      return
    end

    @session = Terminals::Session.find(@session_id)
    if @session.nil?
      reject
      return
    end

    stream_from "terminal:#{@session_id}:output"

    # Replay scrollback on connect — matches Go's 64KB replay on WebSocket reconnect.
    # ActionCable's #transmit takes a positional payload (not kwargs).
    transmit({ type: "scrollback", data: Base64.strict_encode64(@session.scrollback.dup) })
  end

  def unsubscribed
    # Sessions outlive any single browser tab — leave the PTY running so
    # a refresh doesn't kill the shell. Reaping happens via TTL or explicit
    # close by the user.
  end

  # Called when the browser sends input or resize. ActionCable hands us
  # the data argument as parsed JSON.
  # Expected payload: { "data" => "<base64-encoded-bytes>" }
  def receive(payload)
    return if @session.nil?

    decoded = Base64.strict_decode64(payload.fetch("data"))
    @session.write(decoded)
  rescue ArgumentError, KeyError
    # Malformed payload — silently drop
  end
end
