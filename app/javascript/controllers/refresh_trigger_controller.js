import { Controller } from "@hotwired/stimulus"

// Triggers a forced refresh on a target element's polling controller. When the
// same element also hosts a loading-button controller, its loading state is held
// for the duration of the refresh so the button shows a spinner while it runs.
export default class extends Controller {
  static values = { targetId: String }

  async trigger() {
    const el = document.getElementById(this.targetIdValue)
    const polling = el && this.application.getControllerForElementAndIdentifier(el, "polling")
    if (!polling) return

    const loading = this.application.getControllerForElementAndIdentifier(this.element, "loading-button")
    loading?.start()
    try {
      await polling.refresh()
    } finally {
      loading?.end()
    }
  }
}
