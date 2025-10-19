import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["customField", "customInput", "helpText"]
  static values = { 
    freefeedHosts: Object,
    defaultHelpUrl: String 
  }

  connect() {
    this.updateHelpText()
  }

  hostChanged(event) {
    const selectedValue = event.target.value
    
    if (selectedValue === 'custom') {
      this.showCustomField()
    } else {
      this.hideCustomField()
      this.customInputTarget.value = selectedValue
    }
    
    this.updateHelpText()
  }

  customInputChanged() {
    if (this.isCustomSelected()) {
      this.updateHelpText()
    }
  }

  showCustomField() {
    this.customFieldTarget.style.display = 'block'
    this.customInputTarget.focus()
  }

  hideCustomField() {
    this.customFieldTarget.style.display = 'none'
  }

  isCustomSelected() {
    const customRadio = this.element.querySelector('#host_custom')
    return customRadio && customRadio.checked
  }

  getCurrentHost() {
    if (this.isCustomSelected()) {
      return this.customInputTarget.value || this.defaultHelpUrlValue
    }
    
    const checkedRadio = this.element.querySelector('input[name*="[host]"]:checked')
    return checkedRadio ? checkedRadio.value : this.defaultHelpUrlValue
  }

  updateHelpText() {
    const currentHost = this.getCurrentHost()
    const baseUrl = this.normalizeUrl(currentHost)
    const tokenUrl = `${baseUrl}/settings/app-tokens/create?title=Feeder%20App&scopes=manage-posts,manage-groups`
    
    if (this.hasHelpTextTarget) {
      this.helpTextTarget.href = tokenUrl
      this.helpTextTarget.textContent = "FreeFeed settings"
    }
  }

  normalizeUrl(url) {
    if (!url) return this.defaultHelpUrlValue
    return url.replace(/\/$/, '') // Remove trailing slash
  }
}
