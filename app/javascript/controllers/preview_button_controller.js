import { Controller } from "@hotwired/stimulus"

// Drives the manual feed preview:
// - keeps the button enabled only when a profile is selected and a source is
//   present (and, for AI profiles, a provider and model are chosen)
// - on click, paints the loading spinner, points the modal's feed-preview frame
//   at the preview endpoint for the selected profile + source (plus the chosen
//   provider + model for AI profiles), then opens the modal
// - on modal close, clears the frame so the polling host unmounts (stops polling)
export default class extends Controller {
  static targets = ["button", "frame"]
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
    const profileKey = this._selectedProfileKey()
    if (!profileKey || !this.sourceValue.trim() || !this.hasFrameTarget) return

    const sourceKey = this.sourceKeysValue[profileKey]
    if (!sourceKey) return

    const url = new URL(this.endpointValue, window.location.origin)
    url.searchParams.set("profile_key", profileKey)
    url.searchParams.set(`params[${sourceKey}]`, this.sourceValue)
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
    const profileKey = this._selectedProfileKey()
    let ready = !!profileKey && !!this.sourceValue.trim()
    // AI profiles can't preview until a provider and model are picked.
    if (ready && this._isAiProfile(profileKey)) {
      ready = !!this._aiCredentialValue() && !!this._aiModelValue()
    }
    this.buttonTarget.disabled = !ready
  }

  _selectedProfileKey() {
    const checked = this.element.querySelector("input[name='feed[feed_profile_key]']:checked")
    if (checked) return checked.value
    const hidden = this.element.querySelector("input[type=hidden][name='feed[feed_profile_key]']")
    return hidden ? hidden.value : null
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
