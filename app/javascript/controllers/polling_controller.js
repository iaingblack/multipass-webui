import { Controller } from "@hotwired/stimulus"

// Polls a turbo-frame's src URL on an interval, refreshing the frame's
// contents without disturbing the rest of the page. Pauses when the
// tab is hidden (document.visibilityState) and resumes on refocus —
// mirrors the Go usePolling.js composable's visibility handling.
//
// Usage:
//   <div data-controller="polling"
//        data-polling-interval-value="3000"
//        data-polling-frame-id-value="tree">
//     ...frame contents...
//   </div>
export default class extends Controller {
  static values = { interval: Number, frameId: String }

  connect() {
    this.timer = null
    this.visible = true

    this.onVisibilityChange = this.onVisibilityChange.bind(this)
    document.addEventListener("visibilitychange", this.onVisibilityChange)

    this.start()
    // Refresh-on-focus: if the tab just regained visibility, fire immediately.
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") this.refresh()
    })
  }

  disconnect() {
    this.stop()
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
  }

  onVisibilityChange() {
    if (document.visibilityState === "hidden") this.stop()
    else this.start()
  }

  start() {
    if (this.timer) return
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  stop() {
    if (!this.timer) return
    clearInterval(this.timer)
    this.timer = null
  }

  refresh() {
    const frame = document.getElementById(this.frameIdValue)
    if (frame) Turbo.visit(frame.src, { frame: this.frameIdValue, action: "replace" })
  }
}
