import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "helpText"]
  static values = {
    loadingText: String,
    defaultText: String
  }

  connect() {
    const tokenSelect = this.element.querySelector('select[name="feed[access_token_id]"]')
    if (tokenSelect?.value) {
      this.loadGroups(tokenSelect.value)
    }
  }

  refresh(event) {
    this.loadGroups(event.target.value)
  }

  async loadGroups(tokenId) {
    if (!tokenId) {
      this.showEmptyState()
      return
    }

    this.showLoadingState()

    const response = await fetch(`/access_tokens/${tokenId}/groups`, {
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-Requested-With': 'XMLHttpRequest',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    })

    if (response.ok) {
      const html = await response.text()
      Turbo.renderStreamMessage(html)
      this.showDefaultState()
    }
  }

  showEmptyState() {
    this.selectTarget.disabled = true
    this.selectTarget.innerHTML = '<option value="">Choose target group...</option>'
    this.helpTextTarget.textContent = this.defaultTextValue
    this.helpTextTarget.classList.remove('text-muted')
  }

  showLoadingState() {
    this.selectTarget.disabled = true
    this.selectTarget.innerHTML = '<option value="">Loading...</option>'
    this.helpTextTarget.textContent = this.loadingTextValue
    this.helpTextTarget.classList.add('text-muted')
  }

  showDefaultState() {
    this.helpTextTarget.textContent = this.defaultTextValue
    this.helpTextTarget.classList.remove('text-muted')
  }
}