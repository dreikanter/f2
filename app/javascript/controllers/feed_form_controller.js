import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Check if there's already a selected token and load groups
    const tokenSelect = this.element.querySelector('select[name="feed[access_token_id]"]')
    if (tokenSelect && tokenSelect.value) {
      this.loadGroupsForToken(tokenSelect.value)
    }
  }

  loadGroups(event) {
    this.loadGroupsForToken(event.target.value)
  }

  loadGroupsForToken(tokenId) {
    if (!tokenId) {
      // Clear groups if no token selected
      const wrapper = document.getElementById('group-select-wrapper')
      wrapper.querySelector('select').disabled = true
      wrapper.querySelector('select').innerHTML = '<option value="">Choose target group...</option>'
      return
    }

    // Make Turbo Stream request
    fetch(`/access_tokens/${tokenId}/groups`, {
      method: 'GET',
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-Requested-With': 'XMLHttpRequest',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    }).then(response => {
      if (response.ok) {
        return response.text()
      }
      throw new Error('Failed to load groups')
    }).then(html => {
      Turbo.renderStreamMessage(html)
    }).catch(error => {
      console.error('Group loading error:', error)
      // Show error in the UI
      const wrapper = document.getElementById('group-select-wrapper')
      wrapper.innerHTML = `
        <select name="feed[target_group]" id="feed_target_group" class="form-select" disabled>
          <option value="">Error loading groups</option>
        </select>
        <div class="form-text text-danger">Failed to load groups</div>
        <div class="invalid-feedback">Please select a target group.</div>
      `
    })
  }
}
