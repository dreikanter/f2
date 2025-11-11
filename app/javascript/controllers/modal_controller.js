import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Add backdrop click handler
    this.element.addEventListener('click', this.handleBackdropClick.bind(this))

    // Add escape key handler
    this.escapeHandler = this.handleEscape.bind(this)
    document.addEventListener('keydown', this.escapeHandler)

    // Add focus trap handler
    this.focusTrapHandler = this.handleFocusTrap.bind(this)
    document.addEventListener('keydown', this.focusTrapHandler)

    // Store reference to previously focused element when modal opens
    this.previouslyFocusedElement = null

    // Listen for custom show event from trigger
    this.element.addEventListener('modal:show', this.show.bind(this))
  }

  disconnect() {
    document.removeEventListener('keydown', this.escapeHandler)
    document.removeEventListener('keydown', this.focusTrapHandler)
  }

  show(event) {
    if (event) {
      event.preventDefault()
    }

    // Save the currently focused element before showing modal
    this.previouslyFocusedElement = document.activeElement

    // Calculate scrollbar width and add padding to prevent layout shift
    const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth
    document.body.style.paddingRight = `${scrollbarWidth}px`

    // Show the modal
    this.element.classList.remove('hidden')
    this.element.classList.add('flex')
    this.element.setAttribute('aria-hidden', 'false')
    document.body.style.overflow = 'hidden'

    // Focus the modal container or its first focusable element
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

    // Restore focus to previously focused element
    if (this.previouslyFocusedElement && this.previouslyFocusedElement.focus) {
      this.previouslyFocusedElement.focus()
      this.previouslyFocusedElement = null
    }
  }

  confirm(event) {
    // Close the modal (form submission will proceed)
    this.close()
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

  handleFocusTrap(event) {
    // Only trap focus when modal is visible
    if (this.element.classList.contains('hidden')) {
      return
    }

    // Only trap Tab and Shift+Tab
    if (event.key !== 'Tab') {
      return
    }

    // Get all focusable elements within the modal
    const focusableElements = this.element.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
    const focusableArray = Array.from(focusableElements)
    const firstElement = focusableArray[0]
    const lastElement = focusableArray[focusableArray.length - 1]

    // If Shift+Tab on first element, move to last
    if (event.shiftKey && document.activeElement === firstElement) {
      event.preventDefault()
      lastElement.focus()
    }
    // If Tab on last element, move to first
    else if (!event.shiftKey && document.activeElement === lastElement) {
      event.preventDefault()
      firstElement.focus()
    }
  }
}
