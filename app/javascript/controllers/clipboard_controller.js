import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    text: String
  }

  copy(event) {
    event.preventDefault()

    const button = event.currentTarget
    const originalHTML = button.innerHTML
    const originalTitle = button.title

    navigator.clipboard.writeText(this.textValue).then(() => {
      button.innerHTML = '✓'
      button.title = 'Copied!'
      button.classList.add('text-success')
      button.classList.remove('text-muted')

      setTimeout(() => {
        button.innerHTML = originalHTML
        button.title = originalTitle
        button.classList.remove('text-success')
        button.classList.add('text-muted')
      }, 2000)
    }).catch(err => {
      console.error('Failed to copy text: ', err)
    })
  }
}
