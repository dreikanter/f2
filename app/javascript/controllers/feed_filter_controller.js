import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  navigate() {
    const url = new URL(window.location)
    url.searchParams.delete("page")
    if (this.element.value) {
      url.searchParams.set("feed_id", this.element.value)
    } else {
      url.searchParams.delete("feed_id")
    }
    window.location = url
  }
}
