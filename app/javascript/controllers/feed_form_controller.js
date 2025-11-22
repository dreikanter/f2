import { Controller } from "@hotwired/stimulus"

// Manages feed form submit button label based on enable checkbox state.
// When creating a new feed, updates button text to reflect whether the feed
// will be enabled ("Create and Enable Feed") or disabled ("Create Feed").
export default class extends Controller {
  static targets = ["enableCheckbox", "submitButton"]

  connect() {
    this.updateSubmitButtonLabel()
  }

  updateSubmitButtonLabel() {
    if (!this.hasSubmitButtonTarget || !this.hasEnableCheckboxTarget) return

    const isEnabled = this.enableCheckboxTarget.checked
    const isNew = this.submitButtonTarget.dataset.mode === 'new'

    if (isNew) {
      this.submitButtonTarget.textContent = isEnabled ?
        'Create and Enable Feed' :
        'Create Feed'
    }
  }
}
