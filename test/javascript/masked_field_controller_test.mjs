import assert from "node:assert/strict"
import { afterEach, beforeEach, test } from "node:test"
import { JSDOM } from "jsdom"
import { Application } from "@hotwired/stimulus"
import MaskedFieldController from "controllers/masked_field_controller"
import ClipboardController from "controllers/clipboard_controller"

const masked = "curl --header 'Authorization: Bearer ••••••••'"
const revealed = "curl --header 'Authorization: Bearer test-secret'"
let dom, application, field, button, copied

beforeEach(async () => {
  dom = new JSDOM(`
    <textarea readonly data-controller="masked-field"
              data-masked-field-revealed-value="${revealed}"
              data-action="focus->masked-field#reveal blur->masked-field#hide turbo:before-cache@document->masked-field#hide">${masked}</textarea>
    <button data-controller="clipboard" data-clipboard-text-value="${revealed}"
            data-action="click->clipboard#copy">Copy</button>
  `, { url: "http://localhost" })
  const { window } = dom
  Object.assign(globalThis, {
    window, document: window.document, MutationObserver: window.MutationObserver,
    Node: window.Node, Element: window.Element, HTMLElement: window.HTMLElement,
    KeyboardEvent: window.KeyboardEvent, MouseEvent: window.MouseEvent
  })
  copied = []
  Object.defineProperty(globalThis.navigator, "clipboard", {
    configurable: true,
    value: { writeText: async (text) => { copied.push(text) } }
  })
  field = document.querySelector("textarea")
  button = document.querySelector("button")
  application = Application.start()
  application.register("masked-field", MaskedFieldController)
  application.register("clipboard", ClipboardController)
  await new Promise(resolve => setTimeout(resolve, 0))
})

afterEach(async () => {
  document.body.replaceChildren()
  await new Promise(resolve => setTimeout(resolve, 0))
  application.stop()
  dom.window.close()
  delete globalThis.navigator.clipboard
})

test("reveals the command on focus and masks it again on blur", () => {
  assert.equal(field.value, masked)
  field.focus()
  assert.equal(field.value, revealed)
  field.blur()
  assert.equal(field.value, masked)
  field.focus()
  assert.equal(field.value, revealed)
})

test("masks a focused command before Turbo caches the page", () => {
  field.focus()
  document.dispatchEvent(new dom.window.Event("turbo:before-cache"))
  assert.equal(field.value, masked)
  assert.equal(field.defaultValue, masked)
})

test("copies the real command while the field is masked", async () => {
  button.click()
  await Promise.resolve()
  assert.deepEqual(copied, [revealed])
  assert.equal(field.value, masked)
})

test("copies the real command after focus moves to Copy", async () => {
  field.focus()
  button.focus()
  assert.equal(field.value, masked)
  button.click()
  await Promise.resolve()
  assert.deepEqual(copied, [revealed])
})
