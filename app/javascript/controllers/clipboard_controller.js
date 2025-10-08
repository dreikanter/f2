import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    text: String
  }

  copy(event) {
    event.preventDefault()

    navigator.clipboard.writeText(this.textValue).then(() => {
      const originalText = event.currentTarget.innerHTML
      event.currentTarget.innerHTML = '✓ Copied!'
      event.currentTarget.classList.add('btn-success')
      event.currentTarget.classList.remove('btn-outline-secondary')

      setTimeout(() => {
        event.currentTarget.innerHTML = originalText
        event.currentTarget.classList.remove('btn-success')
        event.currentTarget.classList.add('btn-outline-secondary')
      }, 2000)
    }).catch(err => {
      console.error('Failed to copy text: ', err)
    })
  }
}
