import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tokenSelect", "enabledCheckbox"]

  connect() {
    this.updateCheckboxState()
  }

  updateCheckboxState() {
    const hasToken = this.tokenSelectTarget.value !== ""
    
    if (hasToken) {
      this.enabledCheckboxTarget.disabled = false
    } else {
      this.enabledCheckboxTarget.disabled = true
      this.enabledCheckboxTarget.checked = false
    }
  }
}