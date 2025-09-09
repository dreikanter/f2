import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { accessTokenId: String }
  
  connect() {
    if (this.hasAccessTokenIdValue) {
      this.startPolling();
    }
  }
  
  startPolling() {
    this.interval = setInterval(() => {
      fetch(`/access_tokens/${this.accessTokenIdValue}/status`, {
        headers: { 
          "Accept": "text/vnd.turbo-stream.html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })
      .then(response => response.text())
      .then(html => {
        // Process the Turbo Stream response
        Turbo.renderStreamMessage(html);
        
        // Stop polling after first status update is received
        clearInterval(this.interval);
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
