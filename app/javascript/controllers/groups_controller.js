import { Controller } from "@hotwired/stimulus"

// Loads the target-group selector for the chosen access token: fetches the
// groups endpoint and lets the returned turbo-stream replace the selector
// partial (including its server-rendered error states).
export default class extends Controller {
  static targets = ["tokenSelect"]
  static values = { endpoint: String }

  connect() {
    if (this.hasTokenSelectTarget && this.tokenSelectTarget.value && !this.tokenSelectTarget.disabled) {
      this.loadGroups(this.tokenSelectTarget.value)
    }
  }

  refresh(event) {
    this.loadGroups(event.target.value)
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
