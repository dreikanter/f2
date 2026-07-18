import { Controller } from "@hotwired/stimulus"

// Forces a fresh preview run from inside the feed-preview frame (the "Refresh
// preview" / "Try again" buttons). POSTs to the preview endpoint (which busts
// the cached run) and reloads the enclosing turbo-frame so the polling host
// remounts and resumes polling.
export default class extends Controller {
  static values = { refreshUrl: String }

  async refresh(event) {
    event?.preventDefault()
    if (!this.hasRefreshUrlValue) return

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const response = await fetch(this.refreshUrlValue, {
        method: "POST",
        headers: {
          Accept: "text/html",
          "X-CSRF-Token": csrfToken,
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (!response.ok) throw new Error(`Preview refresh failed with HTTP ${response.status}`)

      this.reloadFrame()
    } catch (error) {
      console.error("Failed to refresh preview", error)
      window.alert("Unable to refresh the preview. Please try again.")
    }
  }

  reloadFrame() {
    const frame = this.element.closest("turbo-frame#feed-preview")
    if (frame && typeof frame.reload === "function") {
      frame.reload()
    } else if (frame) {
      const src = frame.getAttribute("src")
      frame.setAttribute("src", "")
      frame.setAttribute("src", src)
    }
  }
}
