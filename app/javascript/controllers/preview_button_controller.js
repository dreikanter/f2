import { Controller } from "@hotwired/stimulus"
import { selectedProfileKey } from "controllers/helpers/selected_profile_key"
import { csrfToken } from "controllers/helpers/csrf_token"

// Keeps preview availability in sync with the form and POSTs the current source
// and provider selections when opening the modal. Closing it aborts the request
// and unmounts any active poller.
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
    this._abortInFlight()
    this._modal?.removeEventListener("modal:hide", this._onHide)
    this.element.removeEventListener("change", this._onFormChange)
  }

  // A request whose answer nobody wants any more: the modal closed, or a newer
  // open superseded it. Left running, its response would mount a poller into a
  // closed frame, or a slow earlier one would overwrite a newer preview.
  _abortInFlight() {
    this._inFlight?.abort()
    this._inFlight = null
  }

  async open(event) {
    event?.preventDefault()
    const profileKey = selectedProfileKey(this.element)
    if (!profileKey || !this._currentSource().trim() || !this.hasFrameTarget) return

    const sourceKey = this.sourceKeysValue[profileKey]
    if (!sourceKey) return

    // Paint the spinner before kicking off the request so the modal never opens
    // empty while the first response is in flight.
    if (this._loadingHTML != null) this.frameTarget.innerHTML = this._loadingHTML
    this._modal?.dispatchEvent(new CustomEvent("modal:show"))

    this._abortInFlight()
    const request = new AbortController()
    this._inFlight = request

    try {
      const response = await fetch(this.endpointValue, {
        method: "POST",
        headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": csrfToken() },
        body: this._requestBody(profileKey, sourceKey),
        credentials: "same-origin",
        signal: request.signal
      })
      if (response.ok) Turbo.renderStreamMessage(await response.text())
    } catch {
      // Aborted, or a network failure: either way nothing renders, and the
      // spinner stays until the next attempt.
    } finally {
      if (this._inFlight === request) this._inFlight = null
    }
  }

  // The preview reads what the form holds, and the form holds more than a URL,
  // so it travels in the body rather than the query string.
  _requestBody(profileKey, sourceKey) {
    const body = new URLSearchParams()
    body.set("profile_key", profileKey)
    body.set(`params[${sourceKey}]`, this._currentSource())

    if (this._isAiProfile(profileKey)) {
      const credential = this._aiCredentialValue()
      const searchCredential = this._searchCredentialValue()
      const model = this._aiModelValue()
      if (credential) body.set("ai_credential_id", credential)
      if (searchCredential) body.set("search_credential_id", searchCredential)
      if (model) body.set("ai_model", model)
    }

    return body
  }

  refreshAvailability() {
    if (!this.hasButtonTarget) return
    const reason = this._unavailableReason()
    this.buttonTarget.disabled = reason != null
    this._showHint(reason)
  }

  // What's still missing before a preview can run, phrased for the user, or null
  // when it's ready. Mirrors the enable checks so the hint never disagrees with
  // the button.
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

  _searchCredentialValue() {
    return this.element.querySelector("select[name='feed[search_credential_id]']")?.value || ""
  }

  _aiModelValue() {
    return this.element.querySelector("select[name='feed[ai_model]']")?.value || ""
  }

  _clearFrame() {
    if (!this.hasFrameTarget) return

    // Removing src alone won't clear the frame's children, so the inner polling
    // host would keep running. Emptying innerHTML removes it from the DOM, which
    // fires its disconnect() and stops polling. Reopening re-sets src and reloads.
    this._abortInFlight()
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = ""
  }
}
