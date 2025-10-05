import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "helpText", "tokenSelect"]
  static values = {
    loadingText: String,
    defaultText: String,
    endpoint: String,
    scope: String
  }

  connect() {
    if (this.hasTokenSelectTarget && this.tokenSelectTarget.value && !this.tokenSelectTarget.disabled) {
      this.loadGroups(this.tokenSelectTarget.value)
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

    // Store the current selected value to restore it after loading
    const currentValue = this.hasSelectTarget ? this.selectTarget.value : null

    this.showLoadingState()

    let url = this.endpointValue.replace(':access_token_id', tokenId)
    const params = new URLSearchParams()

    if (currentValue) {
      params.append('selected_group', currentValue)
    }

    if (this.hasScopeValue) {
      params.append('scope', this.scopeValue)
    }

    if (params.toString()) {
      url += `?${params.toString()}`
    }

    try {
      const response = await fetch(url, {
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
      } else {
        this.showErrorState()
      }
    } catch (error) {
      this.showErrorState()
    }
  }

  showEmptyState() {
    if (!this.hasSelectTarget) return

    this.selectTarget.disabled = true
    this.selectTarget.innerHTML = '<option value="">Choose target group...</option>'
    if (this.hasHelpTextTarget) {
      this.helpTextTarget.textContent = this.defaultTextValue
      this.helpTextTarget.classList.remove('text-muted')
    }
  }

  showLoadingState() {
    if (!this.hasSelectTarget) return

    this.selectTarget.disabled = true
    this.selectTarget.innerHTML = '<option value="">Loading...</option>'
    if (this.hasHelpTextTarget) {
      this.helpTextTarget.textContent = this.loadingTextValue
      this.helpTextTarget.classList.add('text-muted')
    }
  }

  showDefaultState() {
    if (!this.hasHelpTextTarget) return

    this.helpTextTarget.textContent = this.defaultTextValue
    this.helpTextTarget.classList.remove('text-muted')
  }

  showErrorState() {
    if (!this.hasSelectTarget) return

    this.selectTarget.disabled = true
    this.selectTarget.innerHTML = '<option value="">Error loading groups</option>'
    if (this.hasHelpTextTarget) {
      this.helpTextTarget.textContent = "Unable to load groups. Please try again."
      this.helpTextTarget.classList.add('text-muted')
    }
  }
}
