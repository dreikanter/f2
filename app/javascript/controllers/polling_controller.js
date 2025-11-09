import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    endpoint: String,
    interval: { type: Number, default: 2000 },
    maxPolls: { type: Number, default: 30 },
    stopCondition: String,
    scope: { type: String, default: "element" },
    maxDuration: { type: Number, default: 0 }
  }

  connect() {
    this._originalBusy = this.element.getAttribute("aria-busy")
    if (this.hasEndpointValue) this.startPolling()
  }

  disconnect() {
    this.stopPolling({ restoreBusy: true })
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
    this._startedAt = Date.now()
    this.element.setAttribute("aria-busy", "true")
    this._scheduleNext(0)
  }

  restartPolling() {
    this.stopPolling()
    this.startPolling()
  }

  stopPolling({ restoreBusy = false } = {}) {
    this._running = false
    clearTimeout(this._timerId)
    this._timerId = null
    if (this._abort) this._abort.abort()
    this._abort = null
    if (restoreBusy) {
      if (this._originalBusy === null) this.element.removeAttribute("aria-busy")
      else this.element.setAttribute("aria-busy", this._originalBusy)
    } else {
      this.element.setAttribute("aria-busy", "false")
    }
  }

  _scheduleNext(delayMs) {
    if (!this._running) return
    this._timerId = setTimeout(() => this._tick(), delayMs)
  }

  async _tick() {
    if (!this._running) return

    if (this.stopConditionSatisfied()) return this.stopPolling()
    if (this.maxDurationValue > 0 && Date.now() - this._startedAt > this.maxDurationValue) {
      console.warn("Polling stopped after max duration")
      return this.stopPolling()
    }
    if (this._pollCount >= this.maxPollsValue) {
      console.warn("Polling stopped after maximum attempts")
      return this.stopPolling()
    }
    if (document.hidden) {
      return this._scheduleNext(this.intervalValue)
    }
    if (typeof navigator !== "undefined" && "onLine" in navigator && !navigator.onLine) {
      return this._scheduleNext(this.intervalValue)
    }

    this._pollCount += 1

    this._abort?.abort()
    this._abort = new AbortController()

    try {
      const response = await fetch(this.endpointValue, {
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        signal: this._abort.signal
      })

      if (!response.ok) {
        console.warn(`Polling stopped: ${response.status}`)
        return this.stopPolling()
      }

      const html = await response.text()
      if (html && typeof Turbo !== "undefined" && Turbo.renderStreamMessage) {
        Turbo.renderStreamMessage(html)
      }

      if (this.stopConditionSatisfied()) return this.stopPolling()

      this._scheduleNext(this.intervalValue)
    } catch (err) {
      if (err.name === "AbortError") return
      console.error("Polling error:", err)
      this._scheduleNext(this.intervalValue)
    }
  }

  stopConditionSatisfied() {
    if (!this.hasStopConditionValue) return false
    const selectorInput = this.stopConditionValue.trim()
    if (!selectorInput) return false

    const selectors = this.buildSelectors(selectorInput)
    const root = this.scopeValue === "document" ? document : this.element
    return !!this.findElementFor(root, selectors)
  }

  findElementFor(root, selectors) {
    if (Array.isArray(selectors)) {
      for (const sel of selectors) {
        if (root.matches?.(sel)) return root
        const found = root.querySelector(sel)
        if (found) return found
      }
      return null
    }
    if (root.matches?.(selectors)) return root
    return root.querySelector(selectors)
  }

  buildSelectors(selector) {
    if (/^[\[#.]/.test(selector) || /[\s=>:"'\]]/.test(selector)) return selector

    const parts = selector.split(",").map(s => s.trim()).filter(Boolean)
    if (parts.length > 1) {
      return parts.map(p => this._attrToSelector(p))
    }
    return this._attrToSelector(selector)
  }

  _attrToSelector(token) {
    const eq = token.indexOf("=")
    if (eq === -1) return `[${token}]`
    const name = token.slice(0, eq)
    const value = token.slice(eq + 1)
    const quoted = JSON.stringify(value)
    return `[${name}=${quoted}]`
  }
}
