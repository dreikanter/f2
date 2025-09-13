import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tokenSelect", "groupSelect", "groupLoading"]

  connect() {
    // Load groups if a token is already selected
    if (this.tokenSelectTarget.value) {
      this.loadGroups(this.tokenSelectTarget.value)
    }
  }

  tokenChanged() {
    const tokenId = this.tokenSelectTarget.value
    
    if (tokenId) {
      this.loadGroups(tokenId)
    } else {
      this.clearGroups()
    }
  }

  async loadGroups(tokenId) {
    this.showLoading()
    this.disableGroupSelect()

    try {
      const response = await fetch(`/access_tokens/${tokenId}/groups`, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.populateGroups(data.groups)
      } else {
        const errorData = await response.json()
        this.showError(errorData.error || 'Failed to load groups')
      }
    } catch (error) {
      this.showError('Failed to connect to server')
    } finally {
      this.hideLoading()
    }
  }

  populateGroups(groups) {
    const select = this.groupSelectTarget
    const currentValue = select.value
    
    // Clear existing options except the prompt
    select.innerHTML = '<option value="">Choose target group...</option>'
    
    // Add group options
    groups.forEach(group => {
      const option = document.createElement('option')
      option.value = group.username
      option.textContent = group.screen_name ? `${group.screen_name} (${group.username})` : group.username
      
      if (group.is_private) {
        option.textContent += ' 🔒'
      }
      
      select.appendChild(option)
    })

    // Restore previous selection if it still exists
    if (currentValue) {
      select.value = currentValue
    }

    this.enableGroupSelect()
  }

  clearGroups() {
    const select = this.groupSelectTarget
    select.innerHTML = '<option value="">Choose target group...</option>'
    this.disableGroupSelect()
  }

  showLoading() {
    if (this.hasGroupLoadingTarget) {
      this.groupLoadingTarget.style.display = 'block'
    }
  }

  hideLoading() {
    if (this.hasGroupLoadingTarget) {
      this.groupLoadingTarget.style.display = 'none'
    }
  }

  enableGroupSelect() {
    this.groupSelectTarget.disabled = false
  }

  disableGroupSelect() {
    this.groupSelectTarget.disabled = true
  }

  showError(message) {
    // For now, just log the error. In the future, we could show a user-friendly message
    console.error('Group loading error:', message)
    
    // Clear groups and keep select disabled
    this.clearGroups()
  }
}
