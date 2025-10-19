import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="token-host"
export default class extends Controller {
  static targets = ["hostSelect", "link"]

  connect() {
    this.updateLink()
  }

  updateLink() {
    const host = this.hostSelectTarget.value
    const scopes = "read-my-info%20manage-posts"
    const url = `${host}/settings/app-tokens/create?scopes=${scopes}`

    this.linkTarget.href = url
    this.linkTarget.textContent = host.replace("https://", "")
  }
}
