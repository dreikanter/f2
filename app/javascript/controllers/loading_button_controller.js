import { Controller } from "@hotwired/stimulus"

// Drives a button's loading state across a Turbo form submission:
// - on submit start, disables the button and swaps the default icon for a spinner
// - on submit end, resets it — but never sooner than minDuration after the start,
//   so the spinner stays visible long enough to read even when the server is fast
export default class extends Controller {
  static targets = ["button", "default", "loading"]
  static values = { minDuration: { type: Number, default: 500 } }

  start() {
    this._startedAt = performance.now()
    this._setLoading(true)
  }

  end() {
    // Turbo re-enables its submitter when the request finishes; re-assert the
    // loading state so the button stays disabled until the minimum duration is up.
    this._setLoading(true)
    const elapsed = performance.now() - (this._startedAt ?? 0)
    const remaining = Math.max(0, this.minDurationValue - elapsed)
    setTimeout(() => this._setLoading(false), remaining)
  }

  _setLoading(loading) {
    if (this.hasButtonTarget) this.buttonTarget.disabled = loading
    if (this.hasDefaultTarget) this.defaultTarget.classList.toggle("hidden", loading)
    if (this.hasLoadingTarget) this.loadingTarget.classList.toggle("hidden", !loading)
  }
}
