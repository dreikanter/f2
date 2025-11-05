import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    modalId: String
  }

  open(event) {
    event.preventDefault()
    const modal = document.getElementById(this.modalIdValue)
    if (modal) {
      // Dispatch custom event to trigger the modal's show method
      // This allows the modal controller to handle all focus management
      modal.dispatchEvent(new CustomEvent('modal:show', { bubbles: false }))
    }
  }
}
