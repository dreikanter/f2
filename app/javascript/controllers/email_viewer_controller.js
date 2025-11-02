import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textPanel", "htmlPanel", "textTab", "htmlTab"]

  connect() {
    this.showText()
  }

  showText(event) {
    if (event) event.preventDefault()
    this.activateTab(this.textTabTarget, this.htmlTabTarget)
    this.textPanelTarget.classList.remove("hidden")
    this.htmlPanelTarget.classList.add("hidden")
  }

  showHtml(event) {
    if (event) event.preventDefault()
    this.activateTab(this.htmlTabTarget, this.textTabTarget)
    this.htmlPanelTarget.classList.remove("hidden")
    this.textPanelTarget.classList.add("hidden")
  }

  activateTab(active, inactive) {
    active.classList.add("text-cyan-600", "border-cyan-600")
    active.classList.remove("text-slate-500", "border-transparent")

    inactive.classList.remove("text-cyan-600", "border-cyan-600")
    inactive.classList.add("text-slate-500", "border-transparent")
  }
}
