import { Controller } from "@hotwired/stimulus"

// Two-mode feed entry: switch between the "Follow a feed or channel" (link) and
// "Follow with AI" (ai) panels, keeping the matching toggle button selected.
// Each tab and panel carries a data-mode; the inactive panel's fields are
// disabled so the hidden form neither submits nor blocks required validation.
// Without JS both panels stay visible, so either mode still works.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { mode: { type: String, default: "link" } }

  connect() {
    this.show(this.modeValue)
  }

  select(event) {
    this.show(event.currentTarget.dataset.mode)
  }

  show(mode) {
    this.modeValue = mode

    this.tabTargets.forEach((tab) => {
      tab.setAttribute("aria-pressed", tab.dataset.mode === mode)
    })

    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.mode === mode
      panel.hidden = !active
      panel.querySelectorAll("input, textarea").forEach((field) => { field.disabled = !active })
    })

    this.activePanel(mode)?.querySelector("input, textarea")?.focus()
  }

  activePanel(mode) {
    return this.panelTargets.find((panel) => panel.dataset.mode === mode)
  }
}
