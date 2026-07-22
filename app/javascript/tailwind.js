// Tailwind layout entrypoint shares the base Turbo/Stimulus boot logic and
// gives us a spot for future Tailwind-only enhancements if we need them.
//
// TBD: After Tailwind migration is over, merge this file to application.js
//
import "application"
import "flowbite"

// Close any open Flowbite dropdowns before Turbo caches the page. Otherwise a
// dropdown left open while navigating away (e.g. clicking "Details" in a post
// menu) gets cached in its open state and reappears stuck open on back
// navigation, with Flowbite's click-outside handler no longer wired up.
document.addEventListener("turbo:before-cache", () => {
  document.querySelectorAll("[data-dropdown-toggle]").forEach((toggle) => {
    const menu = document.getElementById(toggle.getAttribute("data-dropdown-toggle"))
    if (menu && !menu.classList.contains("hidden")) {
      menu.classList.add("hidden")
      toggle.setAttribute("aria-expanded", "false")
    }
  })
})

// Close the enclosing dropdown as soon as a menu action submits (e.g. Refresh
// in the feed actions menu). Turbo intercepts these form submits, so no page
// visit closes the menu, and Flowbite only reacts to clicks outside it.
// Closing through the Flowbite instance keeps its internal open state in
// sync — hiding the element directly would make the next trigger click a
// no-op toggle back to hidden.
document.addEventListener("turbo:submit-start", (event) => {
  const menu = event.target.closest('[role="menu"]')
  if (!menu) return

  window.FlowbiteInstances?.getInstance("Dropdown", menu.id)?.hide()
})
