import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Add backdrop click handler
    this.element.addEventListener('click', this.handleBackdropClick.bind(this))

    // Add escape key handler
    this.escapeHandler = this.handleEscape.bind(this)
    document.addEventListener('keydown', this.escapeHandler)
  }

  disconnect() {
    document.removeEventListener('keydown', this.escapeHandler)
  }

  show(event) {
    event.preventDefault()
    this.element.classList.remove('hidden')
    this.element.classList.add('flex')
    this.element.setAttribute('aria-hidden', 'false')
    document.body.style.overflow = 'hidden'
  }

  close(event) {
    if (event) {
      event.preventDefault()
    }
    this.element.classList.add('hidden')
    this.element.classList.remove('flex')
    this.element.setAttribute('aria-hidden', 'true')
    document.body.style.overflow = ''
  }

  confirm(event) {
    // Allow the form submission to proceed
    // The modal will be closed by the page navigation
    document.body.style.overflow = ''
  }

  handleBackdropClick(event) {
    // Close if clicking on the backdrop (not the modal content)
    if (event.target === this.element) {
      this.close(event)
    }
  }

  handleEscape(event) {
    if (event.key === 'Escape' && !this.element.classList.contains('hidden')) {
      this.close(event)
    }
  }
}
