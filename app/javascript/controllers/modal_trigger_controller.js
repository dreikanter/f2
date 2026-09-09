import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    modalId: String
  }

  open(event) {
    event.preventDefault()
    const modal = document.getElementById(this.modalIdValue)
    if (modal) {
      modal.dispatchEvent(new CustomEvent('modal:show', { bubbles: false }))
    }
  }
}
