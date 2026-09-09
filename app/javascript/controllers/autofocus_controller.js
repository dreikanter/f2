import { Controller } from "@hotwired/stimulus"

// Focuses the first [autofocus] input in markup injected after page load,
// where the attribute alone does nothing.
export default class extends Controller {
  connect() {
    const element = this.element.querySelector("[autofocus]")

    if (element) {
      element.focus()
    }
  }
}
