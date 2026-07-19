import { Controller } from "@hotwired/stimulus"

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
      button.innerHTML = '✓'
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
