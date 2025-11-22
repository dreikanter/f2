import { Controller } from "@hotwired/stimulus"

// Manages form element disabling during feed identification process.
// Prevents double-submission by disabling the URL input and submit button
// when the form is submitted, then re-enabling them when the response completes.
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
