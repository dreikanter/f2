import { Controller } from "@hotwired/stimulus"

// The spinner stays up at least this long after the submission starts, so it
// is readable even when the server answers instantly.
const MIN_DURATION_MS = 500

// Drives a button's loading state across a Turbo form submission:
// - on submit start, disables the button and swaps the default icon for a spinner
// - on submit end, resets it, but no sooner than MIN_DURATION_MS after the start
export default class extends Controller {
  static targets = ["button", "default", "loading"]

  start() {
    this._startedAt = performance.now()
    this._setLoading(true)
  }

  end() {
    // Turbo re-enables its submitter when the request finishes; re-assert the
    // loading state so the button stays disabled until the minimum duration is up.
    this._setLoading(true)
    const elapsed = performance.now() - (this._startedAt ?? 0)
    const remaining = Math.max(0, MIN_DURATION_MS - elapsed)
    clearTimeout(this._resetTimer)
    this._resetTimer = setTimeout(() => this._setLoading(false), remaining)
  }

  disconnect() {
    clearTimeout(this._resetTimer)
  }

  _setLoading(loading) {
    if (this.hasButtonTarget) this.buttonTarget.disabled = loading
    if (this.hasDefaultTarget) this.defaultTarget.classList.toggle("hidden", loading)
    if (this.hasLoadingTarget) this.loadingTarget.classList.toggle("hidden", !loading)
  }
}
