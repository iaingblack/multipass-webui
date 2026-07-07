import { Controller } from "@hotwired/stimulus"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import consumer from "../channels/consumer"

// Connects to <div data-controller="terminal" ...>
// Spawns an xterm.js instance, opens an ActionCable subscription to
// TerminalChannel, and bridges binary I/O both ways.
//
// Wire protocol:
//   Browser → Channel:  { data: "<base64-bytes>" }
//     - Plain terminal input
//     - 5-byte resize prefix (0x01 + cols u16 BE + rows u16 BE)
//   Channel → Browser:  { type: "scrollback", data: "<base64>" }
//                       { type: "output",     data: "<base64>" }
export default class extends Controller {
  static values = {
    vmName: String,
    sessionId: String,
  }
  static targets = [ "status" ]

  connect() {
    this.terminal = new Terminal({
      cursorBlink: true,
      fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
      fontSize: 13,
      theme: {
        background: "#1a1a2e",
        foreground: "#e2e8f0",
        cursor: "#3b82f6",
        selectionBackground: "#3b82f655",
      },
    })
    this.fitAddon = new FitAddon()
    this.terminal.loadAddon(this.fitAddon)
    this.terminal.open(this.element)
    this.fitAddon.fit()
    this.terminal.focus()
    this.setStatus("connecting…")

    // Send initial size so the PTY starts at the right winsize.
    this.sendResize()

    // Forward user keystrokes to the PTY via the channel.
    this.terminal.onData((data) => {
      const bytes = new TextEncoder().encode(data)
      this.sendBytes(bytes)
    })

    // Re-fit on window resize, then notify the PTY of the new size.
    this.resizeListener = () => {
      this.fitAddon.fit()
      this.sendResize()
    }
    window.addEventListener("resize", this.resizeListener)

    // Open the ActionCable subscription. The channel will transmit the
    // 64KB scrollback snapshot immediately on subscribe.
    this.subscription = consumer.subscriptions.create(
      {
        channel: "TerminalChannel",
        vm_name: this.vmNameValue,
        session_id: this.sessionIdValue,
      },
      {
        received: (msg) => this.handleMessage(msg),
        connected: () => this.setStatus("connected"),
        disconnected: () => {
          this.setStatus("disconnected")
          this.terminal.writeln("\r\n[ActionCable disconnected]")
        },
        rejected: () => {
          this.setStatus("rejected")
          this.terminal.writeln("\r\n[Subscription rejected — session missing?]")
        },
      }
    )

    // Ping back the actual cols/rows once the terminal has rendered.
    setTimeout(() => this.sendResize(), 50)
  }

  disconnect() {
    window.removeEventListener("resize", this.resizeListener)
    this.subscription?.unsubscribe()
    this.terminal?.dispose()
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  // Private — handle inbound messages from the channel.
  handleMessage(msg) {
    if (!msg || !msg.type) return

    // Both scrollback and output are base64-encoded binary. Decode to
    // Uint8Array and write to xterm.js — xterm accepts both strings and
    // Uint8Array; bytes are the safer path for terminal data (ANSI escapes,
    // UTF-8 multibyte sequences).
    const bytes = Uint8Array.from(atob(msg.data), (c) => c.charCodeAt(0))

    if (msg.type === "scrollback") {
      this.terminal.reset()
      this.terminal.write(bytes)
    } else if (msg.type === "output") {
      this.terminal.write(bytes)
    }
  }

  // Encode + transmit a binary chunk via the channel.
  sendBytes(bytes) {
    const b64 = btoa(String.fromCharCode(...bytes))
    this.subscription?.perform("receive", { data: b64 })
  }

  // Build + transmit the 5-byte resize message:
  // 0x01 + cols (BE u16) + rows (BE u16). Mirrors the Go pty_store
  // resize protocol (handlers_shell.go:77-83).
  sendResize() {
    const cols = this.terminal.cols
    const rows = this.terminal.rows
    const buf = new Uint8Array(5)
    buf[0] = 0x01
    buf[1] = (cols >> 8) & 0xff
    buf[2] = cols & 0xff
    buf[3] = (rows >> 8) & 0xff
    buf[4] = rows & 0xff
    this.sendBytes(buf)
  }
}
