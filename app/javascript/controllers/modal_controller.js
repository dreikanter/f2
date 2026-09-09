import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.backdropClickHandler = this.handleBackdropClick.bind(this)
    this.element.addEventListener('click', this.backdropClickHandler)

    this.escapeHandler = this.handleEscape.bind(this)
    document.addEventListener('keydown', this.escapeHandler)

    this.focusTrapHandler = this.handleFocusTrap.bind(this)
    document.addEventListener('keydown', this.focusTrapHandler)

    this.previouslyFocusedElement = null

    this.showHandler = this.show.bind(this)
    this.element.addEventListener('modal:show', this.showHandler)
  }

  disconnect() {
    this.element.removeEventListener('click', this.backdropClickHandler)
    this.element.removeEventListener('modal:show', this.showHandler)
    document.removeEventListener('keydown', this.escapeHandler)
    document.removeEventListener('keydown', this.focusTrapHandler)
  }

  show(event) {
    if (event) {
      event.preventDefault()
    }

    this.previouslyFocusedElement = document.activeElement

    // Calculate scrollbar width and add padding to prevent layout shift
    const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth
    document.body.style.paddingRight = `${scrollbarWidth}px`

    this.element.classList.remove('hidden')
    this.element.classList.add('flex')
    this.element.setAttribute('aria-hidden', 'false')
    document.body.style.overflow = 'hidden'

    const firstFocusable = this.element.querySelector(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
    if (firstFocusable) {
      firstFocusable.focus()
    } else {
      this.element.focus()
    }
  }

  close(event) {
    if (event) {
      event.preventDefault()
    }
    this.element.classList.add('hidden')
    this.element.classList.remove('flex')
    this.element.setAttribute('aria-hidden', 'true')
    document.body.style.overflow = ''
    document.body.style.paddingRight = ''

    this.element.dispatchEvent(new CustomEvent('modal:hide', { bubbles: true }))

    if (this.previouslyFocusedElement && this.previouslyFocusedElement.focus) {
      this.previouslyFocusedElement.focus()
      this.previouslyFocusedElement = null
    }
  }

  // Closes without preventing the default, so the form submission proceeds.
  confirm() {
    this.close()
  }

  handleBackdropClick(event) {
    if (event.target === this.element) {
      this.close(event)
    }
  }

  handleEscape(event) {
    if (event.key === 'Escape' && !this.element.classList.contains('hidden') && !this.coveredByModal()) {
      this.close(event)
    }
  }

  handleFocusTrap(event) {
    if (this.element.classList.contains('hidden') || this.coveredByModal()) {
      return
    }

    if (event.key !== 'Tab') {
      return
    }

    const focusableElements = this.element.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
    const focusableArray = Array.from(focusableElements)
    const firstElement = focusableArray[0]
    const lastElement = focusableArray[focusableArray.length - 1]

    if (event.shiftKey && document.activeElement === firstElement) {
      event.preventDefault()
      lastElement.focus()
    }
    else if (!event.shiftKey && document.activeElement === lastElement) {
      event.preventDefault()
      firstElement.focus()
    }
  }

  coveredByModal() {
    const visibleModals = document.querySelectorAll('[aria-modal="true"][aria-hidden="false"]')
    return visibleModals[visibleModals.length - 1] !== this.element
  }
}
