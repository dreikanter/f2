import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "controllers/helpers/csrf_token"

// Loads the target-group selector for the chosen access token: fetches the
// groups endpoint and lets the returned turbo-stream replace the selector
// partial (including its server-rendered error states).
export default class extends Controller {
  static targets = ["tokenSelect"]
  static values = { endpoint: String, refreshEndpoint: String }

  connect() {
    if (this.hasTokenSelectTarget && this.tokenSelectTarget.value && !this.tokenSelectTarget.disabled) {
      this.loadGroups(this.tokenSelectTarget.value)
    }
  }

  refresh(event) {
    this.loadGroups(event.target.value)
  }

  // Starts a background refresh of the selected token's groups. The returned
  // turbo-stream swaps the selector into its polling state; the current
  // (possibly unsaved) selection travels along so the swap doesn't reset it.
  // The button can't be a form submit — the selector lives inside the feed
  // form, and forms don't nest.
  async refreshGroups(event) {
    if (!this.hasRefreshEndpointValue || !this.hasTokenSelectTarget) return

    const tokenId = this.tokenSelectTarget.value
    if (!tokenId) return

    // Disable the button before anything awaits, so a double click can't start
    // a second refresh — and do it here rather than leaving it to the
    // loading-button controller, which may not have connected yet.
    const button = event.currentTarget
    if (button.disabled) return
    button.disabled = true

    const loading = this.application.getControllerForElementAndIdentifier(button, "loading-button")
    loading?.start()

    try {
      const url = this.refreshEndpointValue.replace(":access_token_id", tokenId)
      const body = new URLSearchParams()
      const groupSelect = this.element.querySelector('select[name="feed[target_group]"]')
      if (groupSelect?.value) body.set("selected", groupSelect.value)

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": csrfToken()
        },
        body
      })
      if (response.ok) Turbo.renderStreamMessage(await response.text())
    } catch {
      // Network failure: keep the current selector; the button re-enables below.
    } finally {
      if (loading) loading.end()
      else button.disabled = false
    }
  }

  async loadGroups(tokenId) {
    if (!tokenId) return

    const url = this.endpointValue.replace(":access_token_id", tokenId)

    try {
      const response = await fetch(url, { headers: { "Accept": "text/vnd.turbo-stream.html" } })
      if (response.ok) {
        Turbo.renderStreamMessage(await response.text())
      }
    } catch {
      // Network failure: keep the current selector; a token change or reload retries.
    }
  }
}
