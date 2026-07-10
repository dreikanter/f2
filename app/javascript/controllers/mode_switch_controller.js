import { Controller } from "@hotwired/stimulus"

// Reveals the panel matching the checked mode radio. The radios live outside
// the panels' forms, so switching is pure disclosure — each mode keeps its own
// form and fields untouched.
export default class extends Controller {
  static targets = ["radio", "panel"]

  connect() {
    this.sync()
  }

  switch() {
    this.sync({ focus: true })
  }

  sync({ focus = false } = {}) {
    const mode = this.radioTargets.find((radio) => radio.checked)?.value

    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.mode === mode
      panel.hidden = !active
      if (active && focus) panel.querySelector("input:not([type=hidden]):not([type=submit]), textarea")?.focus()
    })
  }
}
