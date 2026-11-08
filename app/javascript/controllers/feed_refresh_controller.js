import PollingController from "controllers/polling_controller"

const TIMEOUT_MESSAGE = "Refresh is taking longer than expected. Reload the page to check its progress."
const ERROR_MESSAGE = "Couldn't check the refresh. Reload the page to try again."

// Keep the polling budget on the page while streams replace its activity and spinner.
export default class extends PollingController {
  static targets = ["progress", "activity", "notice"]

  static values = {
    interval: { type: Number, default: 5000 },
    initialDelay: { type: Number, default: 5000 },
    maxPolls: { type: Number, default: 60 },
    indicateBusy: { type: Boolean, default: false },
    timeout: { type: Number, default: 300000 }
  }

  connect() {
    this._connected = true
    if (this.hasProgressTarget && !this.renderingTurboPreview) this.startPolling()
  }

  disconnect() {
    this._connected = false
    super.disconnect()
  }

  progressTargetConnected() {
    if (this._connected && !this.renderingTurboPreview) this.startPolling()
  }

  progressTargetDisconnected() {
    if (!this.hasProgressTarget) this.stopPolling()
  }

  startPolling() {
    if (this._running) return
    this.noticeTarget.hidden = true
    super.startPolling()
    this._deadlineId = setTimeout(() => {
      this._onTimeout()
      this.stopPolling()
    }, this.timeoutValue)
  }

  stopPolling() {
    clearTimeout(this._deadlineId)
    super.stopPolling()
  }

  _performPoll(options) {
    this.element.dataset.lastEventId = this.activityTarget.dataset.lastEventId || ""
    const url = new URL(this.endpointValue, window.location.href)
    url.searchParams.set("refresh_after", this.progressTarget.dataset.refreshAfter)
    this.endpointValue = url.toString()
    return super._performPoll(options)
  }

  _handlePollResponse(response) {
    if (!this._running) return
    if (!response.ok || response.redirected) return this._fail(ERROR_MESSAGE)
    return super._handlePollResponse(response)
  }

  _handlePollError(error) {
    if (this._running && error.name !== "AbortError") this._fail(ERROR_MESSAGE)
  }

  _onTimeout() {
    this._showNotice(TIMEOUT_MESSAGE)
  }

  _fail(message) {
    this._showNotice(message)
    this.stopPolling()
  }

  _showNotice(message) {
    this.progressTargets.forEach(element => { element.hidden = true })
    this.noticeTarget.textContent = message
    this.noticeTarget.hidden = false
  }
}
