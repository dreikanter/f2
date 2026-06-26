import { Controller } from "@hotwired/stimulus"

// Drives the AI Settings section of the feed form:
// - shows the section only when the selected profile is AI-backed, and
//   disables its selects while hidden so a non-AI feed never submits a
//   provider/model
// - keeps the model list in sync with the chosen provider. Every active
//   credential's models are embedded as a value, so switching providers
//   needs no server round-trip.
export default class extends Controller {
  static targets = ["credentialSelect", "modelSelect"]
  static values = {
    models: Object, // { credentialId: [{ id, name }, ...] }
    aiProfiles: Array // profile keys whose feeds use AI
  }

  connect() {
    this.form = this.element.closest("form")
    this.onFormChange = this._handleFormChange.bind(this)
    this.form?.addEventListener("change", this.onFormChange)
    this.refreshVisibility()
  }

  disconnect() {
    this.form?.removeEventListener("change", this.onFormChange)
  }

  _handleFormChange(event) {
    if (event.target.name === "feed[feed_profile_key]") this.refreshVisibility()
  }

  refreshVisibility() {
    const isAi = this.aiProfilesValue.includes(this._selectedProfileKey())
    this.element.hidden = !isAi
    if (this.hasCredentialSelectTarget) this.credentialSelectTarget.disabled = !isAi
    if (this.hasModelSelectTarget) this.modelSelectTarget.disabled = !isAi
  }

  // Rebuild the model <select> from the chosen credential's models, keeping
  // the current pick if it's still on offer.
  refreshModels() {
    if (!this.hasModelSelectTarget || !this.hasCredentialSelectTarget) return

    const models = this.modelsValue[this.credentialSelectTarget.value] || []
    const previous = this.modelSelectTarget.value
    const keep = models.some((model) => model.id === previous) ? previous : ""

    const options = ['<option value="">Select a model…</option>']
    models.forEach((model) => {
      options.push(`<option value="${this._escape(model.id)}">${this._escape(model.name)}</option>`)
    })
    this.modelSelectTarget.innerHTML = options.join("")
    this.modelSelectTarget.value = keep
  }

  _selectedProfileKey() {
    if (!this.form) return null
    const checked = this.form.querySelector("input[name='feed[feed_profile_key]']:checked")
    if (checked) return checked.value
    const hidden = this.form.querySelector("input[type=hidden][name='feed[feed_profile_key]']")
    return hidden ? hidden.value : null
  }

  _escape(value) {
    const span = document.createElement("span")
    span.textContent = value
    return span.innerHTML.replaceAll('"', "&quot;")
  }
}
