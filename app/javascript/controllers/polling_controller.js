import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    endpoint: String,
    interval: { type: Number, default: 2000 },
    initialDelay: { type: Number, default: 0 },
    maxPolls: { type: Number, default: 30 },
    indicateBusy: { type: Boolean, default: true },
    stopCondition: String,
    scope: { type: String, default: "element" }
  }

  static targets = ["timeoutMessage", "content"]

  connect() {
    if (this.hasEndpointValue) this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    if (this._running) return
    this._running = true
    this._pollCount = 0
    if (this.indicateBusyValue) this.element.setAttribute("aria-busy", "true")
    this._scheduleNext(this.initialDelayValue)
  }

  refresh() {
    if (!this._running) this._running = true
    clearTimeout(this._timerId)
    return this._tick({ force: true })
  }

  stopPolling() {
    this._running = false
    clearTimeout(this._timerId)
    this._timerId = null
    if (this._abort) this._abort.abort()
    this._abort = null
    if (this.indicateBusyValue) this.element.setAttribute("aria-busy", "false")
  }

  _scheduleNext(delayMs) {
    if (!this._running) return
    this._timerId = setTimeout(() => this._tick(), delayMs)
  }

  async _tick(options = {}) {
    if (!this._running) return

    // Skip polling when offline to avoid failed requests
    if (typeof navigator !== "undefined" && "onLine" in navigator && !navigator.onLine) {
      return this._scheduleNext(this.intervalValue)
    }

    if (this.stopConditionSatisfied()) {
      return this.stopPolling()
    }

    if (this.maxPollsValue > 0 && this._pollCount >= this.maxPollsValue) {
      this._onTimeout()
      return this.stopPolling()
    }

    this._pollCount += 1

    try {
      const response = await this._performPoll(options)
      await this._handlePollResponse(response)
    } catch (err) {
      this._handlePollError(err)
    }
  }

  _onTimeout() {
    if (this.hasTimeoutMessageTarget) this.timeoutMessageTarget.hidden = false
    if (this.hasContentTarget) this.contentTarget.hidden = true
  }

  async _performPoll(options = {}) {
    if (this._abort) this._abort.abort()
    this._abort = new AbortController()

    const url = new URL(this.endpointValue, window.location.href)
    if (this.element.dataset.lastEventId) url.searchParams.set("after_id", this.element.dataset.lastEventId)
    if (options.force) url.searchParams.set("force", "1")

    const response = await fetch(url.toString(), {
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-Requested-With": "XMLHttpRequest"
      },
      credentials: "same-origin",
      signal: this._abort.signal
    })

    return response
  }

  async _handlePollResponse(response) {
    if (!response.ok) {
      return this.stopPolling()
    }

    const html = await response.text()
    if (html && typeof Turbo !== "undefined" && Turbo.renderStreamMessage) {
      Turbo.renderStreamMessage(html)
    }

    if (this.stopConditionSatisfied()) {
      return this.stopPolling()
    }

    this._scheduleNext(this.intervalValue)
  }

  _handlePollError(err) {
    if (err.name === "AbortError") return
    console.error("Polling error:", err)
    this._scheduleNext(this.intervalValue)
  }

  stopConditionSatisfied() {
    if (!this.hasStopConditionValue) return false
    const selector = this.stopConditionValue.trim()
    if (!selector) return false

    const root = this.scopeValue === "document" ? document : this.element
    if (root.matches?.(selector)) return true
    return !!root.querySelector(selector)
  }
}
