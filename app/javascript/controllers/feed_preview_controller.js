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
    const loader = document.getElementById('feed_loader')?.value
    const processor = document.getElementById('feed_processor')?.value
    const normalizer = document.getElementById('feed_normalizer')?.value

    if (!url || !loader || !processor || !normalizer) {
      alert('Please fill in all required fields (URL, Loader, Processor, Normalizer) before previewing.')
      return
    }

    // Create form data for preview
    const formData = new FormData()
    formData.append('url', url)
    formData.append('loader', loader)
    formData.append('processor', processor)
    formData.append('normalizer', normalizer)

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
        window.open(response.url, '_blank')
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