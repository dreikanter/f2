import assert from "node:assert/strict"
import { afterEach, beforeEach, test } from "node:test"
import { JSDOM } from "jsdom"
import { Application } from "@hotwired/stimulus"
import PreviewButtonController from "controllers/preview_button_controller"
import ProfileOptionsController from "controllers/profile_options_controller"

let dom, application, form, count, ratio, inactive, requests, invalidFields, modalOpens

beforeEach(async () => {
  dom = new JSDOM(`
    <form data-controller="preview-button" data-preview-button-target="form"
          data-preview-button-endpoint-value="/feed_previews"
          data-preview-button-source-value="https://example.com/feed"
          data-preview-button-source-keys-value='{"first":"url","second":"url"}'
          data-preview-button-modal-id-value="preview">
      <input type="radio" name="feed[feed_profile_key]" value="first" checked>
      <input type="radio" name="feed[feed_profile_key]" value="second">
      <input name="feed[title]" required>
      <div data-controller="profile-options">
        <div data-profile-options-target="group" data-profile-key="first">
          <input type="number" name="feed[params][count]" data-param-name="count" min="1" max="10" step="1" value="3">
          <input type="number" name="feed[params][ratio]" data-param-name="ratio" step="any" value="0.25">
          <input type="hidden" name="feed[params][fancy]" value="0">
          <input type="checkbox" name="feed[params][fancy]" data-param-name="fancy" value="1">
          <select name="feed[params][quality]" data-param-name="quality"><option value="high">High</option></select>
          <input name="feed[params][flavour]" data-param-name="flavour" value="vanilla">
        </div>
        <div data-profile-options-target="group" data-profile-key="second" hidden>
          <input type="number" name="feed[params][count]" data-param-name="count" min="1" max="10" step="1" value="99" disabled>
        </div>
      </div>
      <button type="button" data-preview-button-target="button" data-action="preview-button#open">Preview</button>
      <p data-preview-button-target="hint" hidden></p>
      <div data-preview-button-target="frame">Loading</div>
    </form>
    <div id="preview"></div>
  `, { url: "http://localhost" })
  const { window } = dom
  Object.assign(globalThis, {
    window, document: window.document, MutationObserver: window.MutationObserver,
    Node: window.Node, Element: window.Element, HTMLElement: window.HTMLElement,
    CustomEvent: window.CustomEvent, KeyboardEvent: window.KeyboardEvent,
    MouseEvent: window.MouseEvent, FormData: window.FormData
  })
  requests = []
  invalidFields = []
  modalOpens = 0
  globalThis.fetch = async (_url, options) => {
    requests.push(options.body)
    return { ok: false }
  }
  form = document.querySelector("form")
  count = form.querySelector('[data-profile-key="first"] [data-param-name="count"]')
  ratio = form.querySelector('[data-param-name="ratio"]')
  inactive = form.querySelector('[data-profile-key="second"] [data-param-name="count"]')
  form.addEventListener("invalid", (event) => invalidFields.push(event.target), true)
  document.getElementById("preview").addEventListener("modal:show", () => modalOpens++)
  application = Application.start()
  application.register("preview-button", PreviewButtonController)
  application.register("profile-options", ProfileOptionsController)
  await new Promise(resolve => setTimeout(resolve, 0))
})

afterEach(() => {
  application.stop()
  dom.window.close()
})

function preview() {
  form.querySelector("button").click()
}

test("integer options report fractional values before opening or fetching a preview", () => {
  count.value = "1.5"
  preview()
  assert.equal(count.validity.stepMismatch, true)
  assert.deepEqual(invalidFields, [count])
  assert.equal(requests.length, 0)
  assert.equal(modalOpens, 0)
})

test("integer options reject values below their minimum", () => {
  count.value = "0"
  preview()
  assert.equal(count.validity.rangeUnderflow, true)
  assert.deepEqual(invalidFields, [count])
  assert.equal(requests.length, 0)
})

test("integer options reject values above their maximum", () => {
  count.value = "11"
  preview()
  assert.equal(count.validity.rangeOverflow, true)
  assert.deepEqual(invalidFields, [count])
  assert.equal(requests.length, 0)
})

test("fractional numbers and the lower integer bound preview despite an unrelated required field", () => {
  count.value = "1"
  preview()
  assert.deepEqual(invalidFields, [])
  assert.equal(modalOpens, 1)
  assert.equal(requests[0].get("params[count]"), "1")
  assert.equal(requests[0].get("params[ratio]"), "0.25")
  assert.equal(requests[0].get("params[fancy]"), "0")
  assert.equal(requests[0].get("params[quality]"), "high")
  assert.equal(requests[0].get("params[flavour]"), "vanilla")
})

test("blank optional numeric values remain valid and submit blank", () => {
  count.value = ""
  ratio.value = ""
  preview()
  assert.deepEqual(invalidFields, [])
  assert.equal(requests[0].get("params[count]"), "")
  assert.equal(requests[0].get("params[ratio]"), "")
})

test("inactive options neither block nor contribute to preview and save", () => {
  count.value = "10"
  form.querySelector('[name="feed[title]"]').value = "A feed"
  form.querySelector('[type="checkbox"]').checked = true
  preview()
  assert.equal(inactive.disabled, true)
  assert.equal(form.checkValidity(), true)
  assert.equal(requests[0].get("params[count]"), "10")
  assert.equal(requests[0].get("params[fancy]"), "1")
  assert.deepEqual(new FormData(form).getAll("feed[params][count]"), ["10"])
})

test("switching profiles validates and submits only the newly selected options", async () => {
  const radio = form.querySelector('input[value="second"]')
  radio.checked = true
  radio.dispatchEvent(new window.Event("change", { bubbles: true }))
  preview()
  assert.equal(count.disabled, true)
  assert.equal(inactive.disabled, false)
  assert.deepEqual(invalidFields, [inactive])
  assert.equal(requests.length, 0)

  inactive.value = "4"
  inactive.dispatchEvent(new window.Event("input", { bubbles: true }))
  await Promise.resolve()
  count.value = "99"
  form.querySelector('[name="feed[title]"]').value = "A feed"
  preview()
  assert.equal(requests[0].get("profile_key"), "second")
  assert.equal(requests[0].get("params[count]"), "4")
  assert.equal(requests[0].has("params[ratio]"), false)
  assert.equal(form.checkValidity(), true)
  assert.deepEqual(new FormData(form).getAll("feed[params][count]"), ["4"])
})

test("editing numeric options keeps preview availability and hint in sync", async () => {
  const button = form.querySelector("button")
  const hint = form.querySelector('[data-preview-button-target="hint"]')
  count.value = "1.5"
  count.dispatchEvent(new window.Event("input", { bubbles: true }))
  await Promise.resolve()

  assert.equal(button.disabled, true)
  assert.equal(hint.hidden, false)
  assert.equal(hint.textContent, count.validationMessage)
  assert.deepEqual(invalidFields, [])
  preview()
  assert.equal(requests.length, 0)

  count.value = ""
  count.dispatchEvent(new window.Event("input", { bubbles: true }))
  await Promise.resolve()

  assert.equal(button.disabled, false)
  assert.equal(hint.hidden, true)
  assert.equal(hint.textContent, "")
  preview()
  assert.equal(requests.length, 1)
})

test("switching profiles refreshes availability after panels enable their fields", async () => {
  const button = form.querySelector("button")
  const hint = form.querySelector('[data-preview-button-target="hint"]')
  const second = form.querySelector('input[value="second"]')
  second.checked = true
  second.dispatchEvent(new window.Event("change", { bubbles: true }))
  await Promise.resolve()

  assert.equal(button.disabled, true)
  assert.equal(hint.textContent, inactive.validationMessage)

  const first = form.querySelector('input[value="first"]')
  first.checked = true
  first.dispatchEvent(new window.Event("change", { bubbles: true }))
  await Promise.resolve()

  assert.equal(button.disabled, false)
  assert.equal(hint.hidden, true)
  assert.deepEqual(invalidFields, [])
})
