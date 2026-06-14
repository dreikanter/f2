import { Controller } from "@hotwired/stimulus"

// One-shot catch-up for a cable-pushed update. A turbo_stream_from subscription
// can miss a broadcast that fired before its socket was confirmed. Turbo's
// <turbo-cable-stream-source> sets a "connected" attribute the instant its
// subscription is confirmed, so we wait for that, then fetch the current state
// once and render it if the work already finished. Live broadcasts cover
// everything after — gating on "connected" guarantees we never fetch before the
// subscription is listening, closing the race with no window left.
export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!this.hasUrlValue) return
    this._abort = new AbortController()

    const source = this.element.querySelector("turbo-cable-stream-source")
    if (!source) return this.catchUp()

    if (source.hasAttribute("connected")) {
      this.catchUp()
    } else {
      this._observer = new MutationObserver(() => {
        if (source.hasAttribute("connected")) {
          this._observer.disconnect()
          this._observer = null
          this.catchUp()
        }
      })
      this._observer.observe(source, { attributes: true, attributeFilter: ["connected"] })
    }
  }

  disconnect() {
    this._observer?.disconnect()
    this._abort?.abort()
  }

  async catchUp() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        signal: this._abort.signal
      })

      if (!response.ok) return

      const html = await response.text()
      if (html && typeof Turbo !== "undefined" && Turbo.renderStreamMessage) {
        Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      if (error.name !== "AbortError") throw error
    }
  }
}
