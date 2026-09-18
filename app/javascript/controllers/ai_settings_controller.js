import { Controller } from "@hotwired/stimulus"
import { selectedProfileKey } from "controllers/helpers/selected_profile_key"
import { observeProfileChange } from "controllers/helpers/observe_profile_change"

// Shows the AI Settings section only for AI-backed profiles (disabling its
// selects while hidden so a non-AI feed submits no provider/model), and
// rebuilds the model list from the chosen provider's embedded models without a
// server round-trip.
export default class extends Controller {
  static targets = ["credentialSelect", "searchCredentialSelect", "modelSelect"]
  static values = {
    models: Object, // { credentialId: [{ id, name }, ...] }
    defaultModels: Object, // { credentialId: modelId }
    aiProfiles: Array // profile keys whose feeds use AI
  }

  connect() {
    this.form = this.element.closest("form")
    this.stopObserving = observeProfileChange(this.form, () => this.refreshVisibility())
    this.refreshVisibility()
  }

  disconnect() {
    this.stopObserving?.()
  }

  refreshVisibility() {
    const isAi = this.aiProfilesValue.includes(selectedProfileKey(this.form))
    this.element.hidden = !isAi
    if (this.hasCredentialSelectTarget) this.credentialSelectTarget.disabled = !isAi
    if (this.hasSearchCredentialSelectTarget) this.searchCredentialSelectTarget.disabled = !isAi
    if (this.hasModelSelectTarget) this.modelSelectTarget.disabled = !isAi
  }

  refreshModels() {
    if (!this.hasModelSelectTarget || !this.hasCredentialSelectTarget) return

    const credentialId = this.credentialSelectTarget.value
    const models = this.modelsValue[credentialId] || []
    const defaultModel = this.defaultModelsValue[credentialId]
    const previous = this.modelSelectTarget.value
    const selected = [defaultModel, previous].find((id) => models.some((model) => model.id === id)) || ""

    const placeholder = new Option("Select a model…", "")
    placeholder.disabled = true
    placeholder.hidden = true
    const options = models.map((model) => new Option(model.name, model.id))

    this.modelSelectTarget.replaceChildren(placeholder, ...options)
    this.modelSelectTarget.value = selected
  }
}
