import { Controller } from "@hotwired/stimulus"

// Forces a fresh preview run from inside the feed-preview frame (the "Refresh
// preview" / "Try again" buttons). POSTs to the preview's own refresh endpoint,
// which restarts the run and streams the processing pane back, so the polling
// host already on the page picks the run up from there.
export default class extends Controller {
  static values = { refreshUrl: String }

  async refresh(event) {
    event?.preventDefault()
    if (!this.hasRefreshUrlValue) return

    try {
      const response = await fetch(this.refreshUrlValue, {
        method: "POST",
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
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
