import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    accessTokenId: String,
    endpoint: String,
    interval: { type: Number, default: 2000 },
    maxPolls: { type: Number, default: 30 },
    stopCondition: String
  }

  connect() {
    if (this.hasAccessTokenIdValue || this.hasEndpointValue) {
      this.startPolling();
    }
  }

  startPolling() {
    let pollCount = 0;
    const maxPolls = this.maxPollsValue;

    this.interval = setInterval(() => {
      pollCount++;

      if (pollCount > maxPolls) {
        console.warn('Polling stopped after maximum attempts');
        clearInterval(this.interval);
        return;
      }

      const endpoint = this.hasEndpointValue
        ? this.endpointValue
        : `/access_tokens/${this.accessTokenIdValue}/validation`;

      fetch(endpoint, {
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

          // Check stop condition
          if (this.hasStopConditionValue && !html.includes(this.stopConditionValue)) {
            clearInterval(this.interval);
          }
          // Legacy behavior for access token validation
          else if (!this.hasStopConditionValue && !this.hasEndpointValue) {
            clearInterval(this.interval);
          }
        }
      })
      .catch(error => {
        console.error('Polling error:', error);
        clearInterval(this.interval);
      });
    }, this.intervalValue);
  }

  disconnect() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }
}
