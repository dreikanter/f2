import { Controller } from "@hotwired/stimulus"

// Autofocus for dynamically loaded form inputs to use when autofocus
// HTML attribute doe not work.
//
export default class extends Controller {
  connect() {
    const element = this.element.querySelector("[autofocus]")

    if (element) {
      element.focus()
    }
  }
}
