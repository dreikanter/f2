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
    const maxPolls = 30;
    
    this.interval = setInterval(() => {
      pollCount++;
      
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
        } else {
          clearInterval(this.interval);
          return null;
        }
      })
      .then(html => {
        if (html) {
          Turbo.renderStreamMessage(html);
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
