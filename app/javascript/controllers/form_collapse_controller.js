import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  cancel(event) {
    event.preventDefault()
    // Find the parent edit-form-container and clear it
    const container = document.getElementById("edit-form-container")
    if (container) {
      container.innerHTML = ""
    }
  }
}
