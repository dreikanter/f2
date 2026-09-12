import { Controller } from "@hotwired/stimulus"

// Keeps "Enable feed" honest about the token picked right now: a feed with no
// access token saves fine, but can't go live. The server renders the initial
// state; this only follows the select afterwards.
export default class extends Controller {
  static targets = ["tokenSelect", "checkbox", "hint", "label"]
  static values = { blockedHint: String, readyHint: String }

  connect() {
    this.sync()
  }

  sync() {
    if (!this.hasTokenSelectTarget || !this.hasCheckboxTarget) return

    const blocked = !this.tokenSelectTarget.value
    this.checkboxTarget.disabled = blocked
    if (blocked) this.checkboxTarget.checked = false

    if (this.hasHintTarget) {
      this.hintTarget.textContent = blocked ? this.blockedHintValue : this.readyHintValue
      if (blocked) this.hintTarget.dataset.key = "form.enable-blocked-note"
      else delete this.hintTarget.dataset.key
    }

    if (!this.hasLabelTarget) return

    this.labelTarget.classList.toggle("text-muted", blocked)
    this.labelTarget.classList.toggle("text-heading", !blocked)
  }
}
