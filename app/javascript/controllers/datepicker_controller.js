import { Controller } from "@hotwired/stimulus"
import "flowbite"
import { format } from "date-fns"

// Flowbite's own format tokens, not date-fns': the same ISO shape spelled
// differently by each library.
const PICKER_FORMAT = "yyyy-mm-dd"

// Attaches the Flowbite datepicker to its input. Flowbite only auto-inits
// `datepicker` attributes on turbo:load, which never fires for markup
// injected via Turbo Streams (e.g. the expanded feed form), so inputs opt
// in through this controller instead.
export default class extends Controller {
  connect() {
    if (!window.Datepicker || this.element.datepicker) return

    if (!this.element.value) {
      this.element.value = this.#today()
    }

    this.picker = new window.Datepicker(
      this.element,
      { format: PICKER_FORMAT, autohide: true },
      { id: this.element.id || this.element.name, override: true }
    )
  }

  disconnect() {
    if (this.picker) {
      this.picker.destroyAndRemoveInstance()
      this.picker = null
    }
  }

  reset() {
    this.element.value = this.#today()
    this.picker?.setDate(new Date())
  }

  #today() {
    return format(new Date(), "yyyy-MM-dd")
  }
}
