import { Controller } from "@hotwired/stimulus"

// Enables the delete submit button only while at least one option is checked.
export default class extends Controller {
  static targets = ["checkbox", "submit"]

  connect() {
    this.update()
  }

  update() {
    if (!this.hasSubmitTarget) return

    const anyChecked = this.checkboxTargets.some((checkbox) => checkbox.checked)
    this.submitTarget.disabled = !anyChecked
  }
}
