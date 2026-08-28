import { Controller } from "@hotwired/stimulus"
import { selectedProfileKey } from "controllers/helpers/selected_profile_key"
import { observeProfileChange } from "controllers/helpers/observe_profile_change"

// Shows the option panel belonging to the profile the form currently has
// selected. The other panels stay in the DOM with their fields disabled, so
// picking a candidate never submits options declared by a profile the user
// didn't choose.
export default class extends Controller {
  static targets = ["group"]

  connect() {
    this.form = this.element.closest("form")
    this.stopObserving = observeProfileChange(this.form, () => this.refreshVisibility())
    this.refreshVisibility()
  }

  disconnect() {
    this.stopObserving?.()
  }

  refreshVisibility() {
    const selected = selectedProfileKey(this.form)

    this.groupTargets.forEach((group) => {
      const live = group.dataset.profileKey === selected
      group.hidden = !live
      group.querySelectorAll("input, select, textarea").forEach((field) => {
        field.disabled = !live
      })
    })
  }
}
