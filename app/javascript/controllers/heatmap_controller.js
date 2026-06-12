import { Controller } from "@hotwired/stimulus"
import tippy from "tippy.js"

export default class extends Controller {
  connect() {
    this.instances = tippy(this.element.querySelectorAll("[data-tippy-content]"))
  }

  disconnect() {
    this.instances?.forEach(instance => instance.destroy())
  }
}
