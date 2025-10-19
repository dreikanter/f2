import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hostSelect", "link"]

  static values = {
    hosts: Object
  }

  connect() {
    this.updateLink()
  }

  updateLink() {
    const selectedUrl = this.hostSelectTarget.value
    const hostConfig = Object.values(this.hostsValue).find(h => h.url === selectedUrl)

    if (hostConfig) {
      this.linkTarget.href = hostConfig.token_url
      this.linkTarget.textContent = hostConfig.domain
    }
  }
}
