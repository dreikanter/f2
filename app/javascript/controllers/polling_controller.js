import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    endpoint: String,
    interval: { type: Number, default: 2000 },
    maxPolls: { type: Number, default: 30 },
    stopCondition: String
  }

  connect() {
    if (this.hasEndpointValue) {
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
        this.element.setAttribute('aria-busy', 'false');
        clearInterval(this.interval);
        return;
      }

      fetch(this.endpointValue, {
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })
      .then(response => {
        if (response.ok) {
          return response.text();
        } else {
          this.element.setAttribute('aria-busy', 'false');
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
        }
      })
      .catch(error => {
        console.error('Polling error:', error);
        this.element.setAttribute('aria-busy', 'false');
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
