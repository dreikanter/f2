import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]

  async open(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    event.preventDefault()
    const trigger = event.currentTarget

    try {
      const { default: GLightbox } = await this._load()
      if (!this.element.isConnected) return

      this._trigger = trigger
      this._lightbox ||= this._buildLightbox(GLightbox)
      this._lightbox.openAt(this.itemTargets.indexOf(trigger))
    } catch (error) {
      window.location.assign(trigger.href)
    }
  }

  disconnect() {
    this._lightbox?.destroy()
    this._lightbox = null
    this._loadPromise = null
  }

  _load() {
    return (this._loadPromise ||= import("glightbox"))
  }

  _buildLightbox(GLightbox) {
    const lightbox = GLightbox({
      elements: this.itemTargets.map((item) => ({
        href: item.href,
        type: "image",
        alt: item.querySelector("img")?.alt || ""
      }))
    })

    lightbox.on("open", () => {
      lightbox.modal?.setAttribute("aria-modal", "true")
      lightbox.modal?.setAttribute("aria-label", "Image gallery")
      lightbox.modal?.querySelector(".gclose")?.focus()
    })
    lightbox.on("close", () => {
      if (this._trigger?.isConnected) this._trigger.focus()
      this._trigger = null
    })

    return lightbox
  }
}
