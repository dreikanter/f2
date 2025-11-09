import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    endpoint: String,
    interval: { type: Number, default: 2000 },
    maxPolls: { type: Number, default: 30 },
    stopCondition: String,
    scope: { type: String, default: "element" }
  }

  connect() {
    if (this.hasEndpointValue) this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  endpointValueChanged() {
    if (this.isConnected) this.restartPolling()
  }

  stopConditionValueChanged() {
    if (this.isConnected && this.stopConditionSatisfied()) this.stopPolling()
  }

  startPolling() {
    if (this._running) return
    this._running = true
    this._pollCount = 0
    this.element.setAttribute("aria-busy", "true")
    this._scheduleNext(0)
  }

  restartPolling() {
    this.stopPolling()
    this.startPolling()
  }

  stopPolling() {
    this._running = false
    clearTimeout(this._timerId)
    this._timerId = null
    if (this._abort) this._abort.abort()
    this._abort = null
    this.element.setAttribute("aria-busy", "false")
  }

  _scheduleNext(delayMs) {
    if (!this._running) return
    this._timerId = setTimeout(() => this._tick(), delayMs)
  }

  async _tick() {
    if (!this._running) return

    if (document.hidden) {
      return this._scheduleNext(this.intervalValue)
    }

    if (typeof navigator !== "undefined" && "onLine" in navigator && !navigator.onLine) {
      return this._scheduleNext(this.intervalValue)
    }

    if (!this._shouldContinuePolling()) {
      return this.stopPolling()
    }

    this._pollCount += 1

    try {
      const response = await this._performPoll()
      await this._handlePollResponse(response)
    } catch (err) {
      this._handlePollError(err)
    }
  }

  _shouldContinuePolling() {
    if (this.stopConditionSatisfied()) return false
    if (this._pollCount >= this.maxPollsValue) return false
    return true
  }

  async _performPoll() {
    if (this._abort) this._abort.abort()
    this._abort = new AbortController()

    const response = await fetch(this.endpointValue, {
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
