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

  activateTab(activeButton, inactiveButton) {
    activeButton.classList.add("text-cyan-600", "border-cyan-600")
    activeButton.classList.remove("text-slate-500", "border-transparent")

    inactiveButton.classList.remove("text-cyan-600", "border-cyan-600")
    inactiveButton.classList.add("text-slate-500", "border-transparent")
  }
}
