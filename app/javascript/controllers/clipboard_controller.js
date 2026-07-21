import { Controller } from "@hotwired/stimulus"

// Lucide "check" (https://lucide.dev/icons/check), matching the markup the
// server-side icon helper renders.
const CHECK_ICON =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" ' +
  'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" ' +
  'stroke-linejoin="round" class="shrink-0 size-4" data-icon="check" aria-hidden="true">' +
  '<path d="M20 6 9 17l-5-5"/></svg>'

export default class extends Controller {
  static values = {
    text: String
  }

  disconnect() {
    clearTimeout(this.resetTimer)
  }

  copy(event) {
    event.preventDefault()

    const button = event.currentTarget
    this.originalHTML ??= button.innerHTML
    this.originalTitle ??= button.title
    clearTimeout(this.resetTimer)

    navigator.clipboard.writeText(this.textValue).then(() => {
      button.innerHTML = CHECK_ICON
      button.title = 'Copied!'
      button.classList.add('text-success')
      button.classList.remove('text-muted')

      this.resetTimer = setTimeout(() => {
        button.innerHTML = this.originalHTML
        button.title = this.originalTitle
        button.classList.remove('text-success')
        button.classList.add('text-muted')
        this.resetTimer = null
      }, 2000)
    }).catch(err => {
      console.error('Failed to copy text: ', err)
    })
  }
}
