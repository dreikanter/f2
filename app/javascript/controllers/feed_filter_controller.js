import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "item"]

  connect() {
    this._observer = new MutationObserver(() => {
      if (this.element.classList.contains("hidden")) {
        this.reset()
      } else {
        this.searchTarget.focus()
      }
    })
    this._observer.observe(this.element, { attributes: true, attributeFilter: ["class"] })
  }

  disconnect() {
    this._observer?.disconnect()
  }

  filter() {
    const query = this.searchTarget.value.toLowerCase()
    this.itemTargets.forEach(item => {
      item.hidden = !item.textContent.toLowerCase().includes(query)
    })
  }

  reset() {
    this.searchTarget.value = ""
    this.itemTargets.forEach(item => { item.hidden = false })
  }
}
