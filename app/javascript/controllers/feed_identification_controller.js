import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton", "urlInput"]

  // Turbo events
  disableForm(event) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
    }
    if (this.hasUrlInputTarget) {
      this.urlInputTarget.disabled = true
    }
  }

  enableForm(event) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
    }
    if (this.hasUrlInputTarget) {
      this.urlInputTarget.disabled = false
    }
  }
}
