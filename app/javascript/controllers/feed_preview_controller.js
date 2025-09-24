import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["url", "loader", "processor", "normalizer"]

  connect() {
    this.previewButton = document.getElementById('preview-button')
    if (this.previewButton) {
      this.previewButton.addEventListener('click', this.preview.bind(this))
    }
  }

  disconnect() {
    if (this.previewButton) {
      this.previewButton.removeEventListener('click', this.preview.bind(this))
    }
  }

  preview() {
    const url = document.getElementById('feed_url')?.value
    const feedProfileId = document.getElementById('feed_feed_profile_id')?.value

    if (!url || !feedProfileId) {
      alert('Please fill in URL and select a Feed Profile before previewing.')
      return
    }

    // Get feed profile name from the selected option
    const feedProfileSelect = document.getElementById('feed_feed_profile_id')
    const selectedOption = feedProfileSelect.options[feedProfileSelect.selectedIndex]
    const feedProfileName = selectedOption?.text

    if (!feedProfileName || feedProfileName === 'Choose feed profile...') {
      alert('Please select a valid Feed Profile before previewing.')
      return
    }

    // Create form data for preview
    const formData = new FormData()
    formData.append('url', url)
    formData.append('feed_profile_name', feedProfileName)

    // Submit preview request
    fetch(this.previewButton.dataset.previewUrl, {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => {
      if (response.redirected) {
        // Redirect in the same window instead of opening new tab
        window.location.href = response.url
      } else {
        return response.text().then(text => {
          console.error('Preview failed:', text)
          alert('Preview failed. Please check your feed configuration.')
        })
      }
    })
    .catch(error => {
      console.error('Preview error:', error)
      alert('Preview failed. Please try again.')
    })
  }
}