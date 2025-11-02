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
        console.warn("Polling stopped after maximum attempts");
        this.stopPolling();
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
          this.stopPolling();
          return null;
        }
      })
      .then(html => {
        if (html) {
          Turbo.renderStreamMessage(html);

          if (this.stopConditionSatisfied()) {
            this.stopPolling();
          }
        }
      })
      .catch(error => {
        console.error("Polling error:", error);
        this.stopPolling();
      });
    }, this.intervalValue);
  }

  disconnect() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }

  stopConditionSatisfied() {
    if (!this.hasStopConditionValue) {
      return false;
    }

    const selector = this.stopConditionValue.trim();
    if (!selector) {
      return false;
    }

    const selectors = this.buildSelectors(selector);
    const element = this.findElementFor(selectors);
    return !element;
  }

  findElementFor(selectors) {
    if (Array.isArray(selectors)) {
      for (const selector of selectors) {
        const found = document.querySelector(selector);
        if (found) return found;
      }
      return null;
    }
    return document.querySelector(selectors);
  }

  stopPolling() {
    if (this.interval) {
      clearInterval(this.interval);
      this.interval = null;
    }
    this.element.setAttribute("aria-busy", "false");
  }

  buildSelectors(selector) {
    if (/^[\[#.]/.test(selector)) {
      return selector;
    }

    return `[${selector}]`;
  }
}
