import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { accessTokenId: String }
  
  connect() {
    if (this.hasAccessTokenIdValue) {
      this.startPolling();
    }
  }
  
  startPolling() {
    let pollCount = 0;
    const maxPolls = 30; // Stop after 60 seconds (30 * 2 seconds)
    
    this.interval = setInterval(() => {
      pollCount++;
      
      // Stop polling after max attempts to prevent infinite loops
      if (pollCount > maxPolls) {
        console.warn('Polling stopped after maximum attempts');
        clearInterval(this.interval);
        return;
      }
      
      fetch(`/access_tokens/${this.accessTokenIdValue}/status`, {
        headers: { 
          "Accept": "text/vnd.turbo-stream.html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })
      .then(response => {
        if (response.ok) {
          return response.text();
        } else if (response.status === 404) {
          // Token was deleted, stop polling
          clearInterval(this.interval);
          return null;
        } else {
          throw new Error(`HTTP ${response.status}`);
        }
      })
      .then(html => {
        if (html) {
          // Process the Turbo Stream response
          Turbo.renderStreamMessage(html);
          
          // Stop polling after first status update is received
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
