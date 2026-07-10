// The profile key the feed form currently has selected: the checked radio
// while the profile chooser is live, otherwise the hidden field that pins the
// profile once it's fixed.
export function selectedProfileKey(root) {
  if (!root) return null
  const checked = root.querySelector("input[name='feed[feed_profile_key]']:checked")
  if (checked) return checked.value
  const hidden = root.querySelector("input[type=hidden][name='feed[feed_profile_key]']")
  return hidden ? hidden.value : null
}
