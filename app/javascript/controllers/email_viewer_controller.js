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
    active.classList.add("text-info", "border-info")
    active.classList.remove("text-muted", "border-transparent")

    inactive.classList.remove("text-info", "border-info")
    inactive.classList.add("text-muted", "border-transparent")
  }
}
