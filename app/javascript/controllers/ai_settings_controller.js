import { Controller } from "@hotwired/stimulus"
import { selectedProfileKey } from "controllers/helpers/selected_profile_key"

// Shows the AI Settings section only for AI-backed profiles (disabling its
// selects while hidden so a non-AI feed submits no provider/model), and
// rebuilds the model list from the chosen provider's embedded models — no
// server round-trip.
export default class extends Controller {
  static targets = ["credentialSelect", "searchCredentialSelect", "modelSelect"]
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
    const isAi = this.aiProfilesValue.includes(selectedProfileKey(this.form))
    this.element.hidden = !isAi
    if (this.hasCredentialSelectTarget) this.credentialSelectTarget.disabled = !isAi
    if (this.hasSearchCredentialSelectTarget) this.searchCredentialSelectTarget.disabled = !isAi
    if (this.hasModelSelectTarget) this.modelSelectTarget.disabled = !isAi
  }

  // Rebuild the model <select> from the chosen credential's models, keeping
  // the current pick if it's still on offer. The placeholder is disabled so a
  // pick can't be cleared by hand, but assigning value = "" below still
  // selects it when the previous pick isn't offered by the new provider.
  refreshModels() {
    if (!this.hasModelSelectTarget || !this.hasCredentialSelectTarget) return

    const models = this.modelsValue[this.credentialSelectTarget.value] || []
    const previous = this.modelSelectTarget.value
    const keep = models.some((model) => model.id === previous) ? previous : ""

    const placeholder = new Option("Select a model…", "")
    placeholder.disabled = true
    placeholder.hidden = true
    const options = models.map((model) => new Option(model.name, model.id))

    this.modelSelectTarget.replaceChildren(placeholder, ...options)
    this.modelSelectTarget.value = keep
  }
}
