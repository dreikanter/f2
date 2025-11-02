import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textPanel", "htmlPanel", "textButton", "htmlButton"]

  connect() {
    this.showText()
  }

  showText() {
    this.textPanelTarget.classList.remove("hidden")
    this.htmlPanelTarget.classList.add("hidden")
    this.textButtonTarget.classList.remove("ff-button--secondary")
    this.htmlButtonTarget.classList.add("ff-button--secondary")
  }

  showHtml() {
    this.textPanelTarget.classList.add("hidden")
    this.htmlPanelTarget.classList.remove("hidden")
    this.textButtonTarget.classList.add("ff-button--secondary")
    this.htmlButtonTarget.classList.remove("ff-button--secondary")
  }
}
