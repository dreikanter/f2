import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    emptyGroupsHtml: String,
    loadingGroupsHtml: String
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
      document.getElementById('groups-select').innerHTML = JSON.parse(this.emptyGroupsHtmlValue)
      return
    }

    // Show loading state
    document.getElementById('groups-select').innerHTML = JSON.parse(this.loadingGroupsHtmlValue)

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
    }
  }

}