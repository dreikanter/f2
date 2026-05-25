import { Controller } from "@hotwired/stimulus"

// Drives the manual feed preview:
// - keeps the button enabled only when a profile is selected and a source is present
// - on click, points the modal's feed-preview frame at the preview endpoint for
//   the currently selected profile + source, then opens the modal
// - on modal close, clears the frame so the polling host unmounts (stops polling)
export default class extends Controller {
  static targets = ["button", "frame"]
  static values = {
    endpoint: String,
    source: String,
    shapes: Object,
    modalId: String
  }

  connect() {
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

    const shape = this.shapesValue[profileKey]
    if (!shape) return

    const url = new URL(this.endpointValue, window.location.origin)
    url.searchParams.set("profile_key", profileKey)
    url.searchParams.set(`params[${shape}]`, this.sourceValue)
    this.frameTarget.setAttribute("src", url.toString())

    this._modal?.dispatchEvent(new CustomEvent("modal:show"))
  }

  refreshAvailability() {
    if (!this.hasButtonTarget) return
    const ready = !!this._selectedProfileKey() && !!this.sourceValue.trim()
    this.buttonTarget.disabled = !ready
  }

  _selectedProfileKey() {
    const checked = this.element.querySelector("input[name='feed[feed_profile_key]']:checked")
    if (checked) return checked.value
    const hidden = this.element.querySelector("input[type=hidden][name='feed[feed_profile_key]']")
    return hidden ? hidden.value : null
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
