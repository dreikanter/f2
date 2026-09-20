import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { revealed: String }

  connect() {
    this.maskedValue = this.element.defaultValue
    this.hide()
  }

  reveal() {
    this.element.value = this.revealedValue
  }

  hide() {
    this.element.value = this.maskedValue
  }
}
