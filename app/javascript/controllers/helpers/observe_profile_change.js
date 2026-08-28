// The feed form's profile changes while the candidate chooser is live, and
// more than one section reacts to it. Calls back on each pick and returns the
// teardown, so the listener is registered and removed in one place.
export function observeProfileChange(form, callback) {
  if (!form) return () => {}

  const listener = (event) => {
    if (event.target.name === "feed[feed_profile_key]") callback()
  }

  form.addEventListener("change", listener)
  return () => form.removeEventListener("change", listener)
}
