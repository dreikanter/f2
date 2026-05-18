import { Controller } from "@hotwired/stimulus"

// Manages the candidate-chooser radio group on the feed creation form.
// On selection change, emits a `feed:candidate-changed` event carrying the
// chosen profile key so the preview controller can reload its frame.
export default class extends Controller {
  static targets = ["option"]

  switch(event) {
    const profileKey = event.target.value
    if (!profileKey) return

    this.element.dispatchEvent(new CustomEvent("feed:candidate-changed", {
      bubbles: true,
      detail: { profileKey }
    }))
  }
}
