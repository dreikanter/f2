import { Controller } from "@hotwired/stimulus"

// Shows a panel of inputs while a checkbox is checked; hides the panel and
// clears the inputs when it's unchecked.
export default class extends Controller {
  static targets = ["checkbox", "panel", "input"]

  connect() {
    this.update()
  }

  toggle() {
    this.update({ clearWhenHidden: true })
  }

  update({ clearWhenHidden = false } = {}) {
    const enabled = this.checkboxTarget.checked
    this.panelTarget.classList.toggle("hidden", !enabled)

    if (!enabled && clearWhenHidden) {
      this.inputTargets.forEach((input) => { input.value = "" })
    }
  }
}
