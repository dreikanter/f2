import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hostSelect", "link"]

  static values = {
    tokenUrl: String
  }

  connect() {
    this.updateLink()
  }

  updateLink() {
    const host = this.hostSelectTarget.value
    const url = this.tokenUrlValue.replace("{host}", host)

    this.linkTarget.href = url
    this.linkTarget.textContent = host.replace("https://", "")
  }
}
