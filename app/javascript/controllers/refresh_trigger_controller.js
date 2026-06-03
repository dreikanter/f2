import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { targetId: String }

  trigger() {
    const el = document.getElementById(this.targetIdValue)
    this.application.getControllerForElementAndIdentifier(el, "polling")?.refresh()
  }
}
