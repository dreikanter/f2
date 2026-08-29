import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "controllers/helpers/csrf_token"

// Forces a fresh preview run from inside the feed-preview frame (the "Refresh
// preview" / "Try again" buttons). Updating the preview restarts its run and
// streams the whole frame back, so the polling host mounts fresh and follows
// the new run to completion.
export default class extends Controller {
  static values = { refreshUrl: String }

  disconnect() {
    this._abortInFlight()
  }

  _abortInFlight() {
    this._inFlight?.abort()
    this._inFlight = null
  }

  async refresh(event) {
    event?.preventDefault()
    if (!this.hasRefreshUrlValue) return

    this._abortInFlight()
    const request = new AbortController()
    this._inFlight = request

    try {
      const response = await fetch(this.refreshUrlValue, {
        method: "PATCH",
        headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": csrfToken() },
        credentials: "same-origin",
        signal: request.signal
      })

      if (!response.ok) throw new Error(`Preview refresh failed with HTTP ${response.status}`)

      Turbo.renderStreamMessage(await response.text())
    } catch (error) {
      if (error.name === "AbortError") return

      console.error("Failed to refresh preview", error)
      window.alert("Unable to refresh the preview. Please try again.")
    } finally {
      if (this._inFlight === request) this._inFlight = null
    }
  }
}
