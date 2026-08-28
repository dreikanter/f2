// Rails verifies a same-origin browser request by its origin headers and only
// falls back to the token when those are missing, so this covers the fallback
// rather than every request. Cheap enough to always send.
export function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content || ""
}
