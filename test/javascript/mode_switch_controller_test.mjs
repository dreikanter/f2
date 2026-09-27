import assert from "node:assert/strict"
import { afterEach, test } from "node:test"
import { JSDOM } from "jsdom"
import { Application } from "@hotwired/stimulus"
import ModeSwitchController from "controllers/mode_switch_controller"

let dom, application, submit, submissions

async function mount({ mode = "link", checking = false } = {}) {
  dom = new JSDOM(`
    <div data-controller="mode-switch">
      <fieldset ${checking ? "disabled" : ""}>
        <input type="radio" name="entry_mode" value="link" ${mode === "link" ? "checked" : ""}
               data-mode-switch-target="radio" data-action="change->mode-switch#switch">
        <div data-mode="link" data-mode-switch-target="panel">
          <form id="entry-link-form"><input name="url" required></form>
        </div>
        <input type="radio" name="entry_mode" value="ai" ${mode === "ai" ? "checked" : ""}
               data-mode-switch-target="radio" data-action="change->mode-switch#switch">
        <div data-mode="ai" data-mode-switch-target="panel">
          <form id="entry-ai-form"><textarea name="prompt" required></textarea></form>
        </div>
        <input type="radio" name="entry_mode" value="webhook" ${mode === "webhook" ? "checked" : ""}
               data-mode-switch-target="radio" data-action="change->mode-switch#switch">
        <div data-mode="webhook" data-mode-switch-target="panel">
          <form id="entry-webhook-form"><input type="hidden" name="webhook" value="1"></form>
        </div>
      </fieldset>
      <input type="submit" form="entry-${mode}-form" data-mode-switch-target="submit"
             value="${checking ? "Working…" : "Continue"}" ${checking ? "disabled" : ""}>
    </div>
  `, { url: "http://localhost" })
  const { window } = dom
  Object.assign(globalThis, {
    window, document: window.document, MutationObserver: window.MutationObserver,
    Node: window.Node, Element: window.Element, HTMLElement: window.HTMLElement,
    KeyboardEvent: window.KeyboardEvent, MouseEvent: window.MouseEvent
  })
  submit = document.querySelector("[type=submit]")
  submissions = []
  document.addEventListener("submit", (event) => {
    event.preventDefault()
    assert.equal(event.submitter, submit)
    submissions.push(Object.fromEntries(new window.FormData(event.target)))
  })
  application = Application.start()
  application.register("mode-switch", ModeSwitchController)
  await new Promise(resolve => setTimeout(resolve, 0))
}

afterEach(async () => {
  document.body.replaceChildren()
  await new Promise(resolve => setTimeout(resolve, 0))
  application.stop()
  dom.window.close()
})

test("submits the link form while the hidden AI prompt is empty", async () => {
  await mount()
  document.querySelector("[name=url]").value = "https://example.com/feed.xml"

  submit.click()

  assert.deepEqual(submissions, [{ url: "https://example.com/feed.xml" }])
})

test("switches the shared submit between AI and link while preserving input", async () => {
  await mount()
  const url = document.querySelector("[name=url]")
  const prompt = document.querySelector("[name=prompt]")
  url.value = "https://example.com/feed.xml"

  document.querySelector("[value=ai]").click()
  assert.equal(document.querySelector('[data-mode="link"]').hidden, true)
  assert.equal(document.querySelector('[data-mode="ai"]').hidden, false)
  assert.equal(document.activeElement, prompt)
  submit.click()
  assert.deepEqual(submissions, [])

  prompt.value = "Follow Ruby news"
  submit.click()
  assert.deepEqual(submissions, [{ prompt: "Follow Ruby news" }])

  document.querySelector("[value=link]").click()
  assert.equal(document.activeElement, url)
  submit.click()
  assert.deepEqual(submissions, [
    { prompt: "Follow Ruby news" },
    { url: "https://example.com/feed.xml" }
  ])
  assert.equal(prompt.value, "Follow Ruby news")
})

test("submits webhook mode while both source fields are empty", async () => {
  await mount()
  document.querySelector("[value=webhook]").click()

  assert.equal(document.querySelector('[data-mode="webhook"]').hidden, false)
  submit.click()

  assert.deepEqual(submissions, [{ webhook: "1" }])
})

test("submits AI mode when initially selected", async () => {
  await mount({ mode: "ai" })
  document.querySelector("[name=prompt]").value = "Follow Ruby news"

  submit.click()

  assert.deepEqual(submissions, [{ prompt: "Follow Ruby news" }])
})

test("keeps submission disabled when connecting during a check", async () => {
  await mount({ checking: true })

  assert.equal(submit.disabled, true)
  assert.equal(submit.value, "Working…")
  assert.equal(submit.form.id, "entry-link-form")
  submit.click()

  assert.deepEqual(submissions, [])
})
