import { Controller } from "@hotwired/stimulus"
import { selectedProfileKey } from "controllers/helpers/selected_profile_key"

// Drives the manual feed preview:
// - keeps the button enabled only when a profile is selected and a source is
//   present (and, for AI profiles, a provider and model are chosen)
// - on click, paints the loading spinner, points the modal's feed-preview frame
//   at the preview endpoint for the selected profile + source (plus the chosen
//   provider + model for AI profiles), then opens the modal
// - on modal close, clears the frame so the polling host unmounts (stops polling)
export default class extends Controller {
  static targets = ["button", "frame", "source", "hint"]
  static values = {
    endpoint: String,
    source: String,
    sourceKeys: Object,
    aiProfiles: Array,
    modalId: String
  }

  connect() {
    // Snapshot the frame's initial loading markup so we can paint the spinner
    // instantly on every open, instead of waiting for the first server response.
    if (this.hasFrameTarget) this._loadingHTML = this.frameTarget.innerHTML

    this._onHide = this._clearFrame.bind(this)
    this._modal = document.getElementById(this.modalIdValue)
    this._modal?.addEventListener("modal:hide", this._onHide)

    this._onFormChange = this.refreshAvailability.bind(this)
    this.element.addEventListener("change", this._onFormChange)
    this.refreshAvailability()
  }

  disconnect() {
    this._modal?.removeEventListener("modal:hide", this._onHide)
    this.element.removeEventListener("change", this._onFormChange)
  }

  open(event) {
    event?.preventDefault()
    const profileKey = selectedProfileKey(this.element)
    if (!profileKey || !this._currentSource().trim() || !this.hasFrameTarget) return

    const sourceKey = this.sourceKeysValue[profileKey]
    if (!sourceKey) return

    const url = new URL(this.endpointValue, window.location.origin)
    url.searchParams.set("profile_key", profileKey)
    url.searchParams.set(`params[${sourceKey}]`, this._currentSource())
    if (this._isAiProfile(profileKey)) {
      const credential = this._aiCredentialValue()
      const model = this._aiModelValue()
      if (credential) url.searchParams.set("ai_credential_id", credential)
      if (model) url.searchParams.set("ai_model", model)
    }

    // Paint the spinner before kicking off the fetch so the modal never opens
    // empty while the first response is in flight.
    if (this._loadingHTML != null) this.frameTarget.innerHTML = this._loadingHTML
    this.frameTarget.setAttribute("src", url.toString())

    this._modal?.dispatchEvent(new CustomEvent("modal:show"))
  }

  refreshAvailability() {
    if (!this.hasButtonTarget) return
    const reason = this._unavailableReason()
    this.buttonTarget.disabled = reason != null
    this._showHint(reason)
  }

  // What's still missing before a preview can run, phrased for the user, or null
  // when it's ready. Mirrors the enable checks so the hint never disagrees with
  // the button (spec §4 nicety).
  _unavailableReason() {
    const profileKey = selectedProfileKey(this.element)
    if (!profileKey) return "Pick a feed type to preview."
    if (!this._currentSource().trim()) {
      return this._isAiProfile(profileKey) ? "Add a prompt to preview." : "Add a source URL to preview."
    }
    if (this._isAiProfile(profileKey)) {
      if (!this._aiCredentialValue()) return "Choose an AI provider to preview."
      if (!this._aiModelValue()) return "Choose a model to preview."
    }
    return null
  }

  _showHint(reason) {
    if (!this.hasHintTarget) return
    this.hintTarget.textContent = reason || ""
    this.hintTarget.hidden = reason == null
  }

  // The source is the static value from detection, unless an editable field (an
  // AI feed's prompt) is present — then it's whatever the user has typed.
  _currentSource() {
    return this.hasSourceTarget ? this.sourceTarget.value : this.sourceValue
  }

  _isAiProfile(profileKey) {
    return this.hasAiProfilesValue && this.aiProfilesValue.includes(profileKey)
  }

  _aiCredentialValue() {
    return this.element.querySelector("select[name='feed[ai_credential_id]']")?.value || ""
  }

  _aiModelValue() {
    return this.element.querySelector("select[name='feed[ai_model]']")?.value || ""
  }

  _clearFrame() {
    if (!this.hasFrameTarget) return

    // Removing src alone won't clear the frame's children, so the inner polling
    // host would keep running. Emptying innerHTML removes it from the DOM, which
    // fires its disconnect() and stops polling. Reopening re-sets src and reloads.
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = ""
  }
}
