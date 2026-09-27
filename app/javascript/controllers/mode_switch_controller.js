import { Controller } from "@hotwired/stimulus"

// Separate forms keep validation and submitted fields local to each mode.
export default class extends Controller {
  static targets = ["radio", "panel", "submit"]

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
      if (!active) return

      this.submitTarget.setAttribute("form", panel.querySelector("form").id)
      if (focus) panel.querySelector("input:not([type=hidden]):not([type=submit]), textarea")?.focus()
    })
  }
}
