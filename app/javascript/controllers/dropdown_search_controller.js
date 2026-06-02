import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "item"]

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()
    this.itemTargets.forEach(item => {
      item.hidden = query.length > 0 && !item.textContent.toLowerCase().includes(query)
    })
  }

  reset() {
    if (!this.hasInputTarget) return
    this.inputTarget.value = ""
    this.filter()
  }
}
