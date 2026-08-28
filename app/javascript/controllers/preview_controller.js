import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "controllers/helpers/csrf_token"

// Forces a fresh preview run from inside the feed-preview frame (the "Refresh
// preview" / "Try again" buttons). Updating the preview restarts its run and
// streams the whole frame back, so the polling host mounts fresh and follows
// the new run to completion.
export default class extends Controller {
  static values = { refreshUrl: String }

  async refresh(event) {
    event?.preventDefault()
    if (!this.hasRefreshUrlValue) return

    try {
      const response = await fetch(this.refreshUrlValue, {
        method: "PATCH",
        headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": csrfToken() },
        credentials: "same-origin"
      })

      if (!response.ok) throw new Error(`Preview refresh failed with HTTP ${response.status}`)

      Turbo.renderStreamMessage(await response.text())
    } catch (error) {
      console.error("Failed to refresh preview", error)
      window.alert("Unable to refresh the preview. Please try again.")
    }
  }
}
