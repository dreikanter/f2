import { Controller } from "@hotwired/stimulus"
import "flowbite"

// Attaches the Flowbite datepicker to its input. Flowbite only auto-inits
// `datepicker` attributes on turbo:load, which never fires for markup
// injected via Turbo Streams (e.g. the expanded feed form), so inputs opt
// in through this controller instead.
export default class extends Controller {
  static values = { format: { type: String, default: "yyyy-mm-dd" } }

  connect() {
    if (!window.Datepicker || this.element.datepicker) return

    this.picker = new window.Datepicker(
      this.element,
      { format: this.formatValue, autohide: true },
      { id: this.element.id || this.element.name, override: true }
    )
  }

  disconnect() {
    if (this.picker) {
      this.picker.destroyAndRemoveInstance()
      this.picker = null
    }
  }
}
