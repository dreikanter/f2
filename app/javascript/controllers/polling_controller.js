import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { tokenId: String }
  
  connect() {
    if (this.hasTokenIdValue) {
      this.startPolling();
    }
  }
  
  startPolling() {
    this.interval = setInterval(() => {
      fetch(`/access_tokens/${this.tokenIdValue}/access_token_validation`, {
        headers: { 
          "Accept": "text/vnd.turbo-stream.html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })
      .then(response => response.text())
      .then(html => {
        // Process the Turbo Stream response
        Turbo.renderStreamMessage(html);
        
        // Check if job is complete by looking for final states
        if (html.includes('data-status="active"') || 
            html.includes('data-status="inactive"')) {
          clearInterval(this.interval);
        }
      })
      .catch(error => {
        console.error('Polling error:', error);
        clearInterval(this.interval);
      });
    }, 2000);
  }
  
  disconnect() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }
}