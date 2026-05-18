import { Controller } from "@hotwired/stimulus"

// Manages the preview pane on the feed creation form.
//
// - Reloads the embedded turbo-frame when the user picks a different
//   candidate profile (event from candidate-chooser).
// - Refreshes the frame on demand via the explicit "Refresh preview"
//   button (posts to the preview controller, which busts the cache).
export default class extends Controller {
  static targets = ["frame"]
  static values = {
    refreshUrl: String
  }

  connect() {
    this._onCandidateChanged = this._onCandidateChanged.bind(this)
    document.addEventListener("feed:candidate-changed", this._onCandidateChanged)
  }

  disconnect() {
    document.removeEventListener("feed:candidate-changed", this._onCandidateChanged)
  }

  async refresh(event) {
    event?.preventDefault()
    if (!this.hasRefreshUrlValue) return

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    await fetch(this.refreshUrlValue, {
      method: "POST",
      headers: {
        Accept: "text/html",
        "X-CSRF-Token": csrfToken,
        "X-Requested-With": "XMLHttpRequest"
      },
      credentials: "same-origin"
    })

    this._reloadFrame()
  }

  _onCandidateChanged(event) {
    const profileKey = event.detail?.profileKey
    if (!profileKey || !this.hasFrameTarget) return

    const src = this.frameTarget.getAttribute("src")
    if (!src) return

    const url = new URL(src, window.location.origin)
    url.searchParams.set("profile_key", profileKey)
    this.frameTarget.setAttribute("src", url.toString())
  }

  _reloadFrame() {
    if (!this.hasFrameTarget) return

    if (typeof this.frameTarget.reload === "function") {
      this.frameTarget.reload()
    } else {
      const src = this.frameTarget.getAttribute("src")
      this.frameTarget.setAttribute("src", "")
      this.frameTarget.setAttribute("src", src)
    }
  }
}
