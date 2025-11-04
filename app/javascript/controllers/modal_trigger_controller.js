import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    modalId: String
  }

  open(event) {
    event.preventDefault()
    const modal = document.getElementById(this.modalIdValue)
    if (modal) {
      // Show the modal
      modal.classList.remove('hidden')
      modal.classList.add('flex')
      modal.setAttribute('aria-hidden', 'false')
      document.body.style.overflow = 'hidden'
    }
  }
}
