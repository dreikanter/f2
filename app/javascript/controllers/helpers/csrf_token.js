// Rails requires an authenticity token for non-GET fetch requests. Turbo adds
// it automatically for form submissions; manual fetch calls read the meta tag.
export function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content || ""
}
