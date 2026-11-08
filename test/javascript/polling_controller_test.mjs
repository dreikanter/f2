import assert from "node:assert/strict"
import { afterEach, beforeEach, mock, test } from "node:test"
import { JSDOM } from "jsdom"
import { Application } from "@hotwired/stimulus"
import PollingController from "controllers/polling_controller"

let dom, application, status, requests, respond
const settle = () => new Promise(resolve => setImmediate(resolve))
const markup = (interval = 100) => `
  <div data-controller="polling" data-polling-endpoint-value="/feeds/123.turbo_stream?refresh_after=previous"
       data-polling-interval-value="${interval}" data-polling-initial-delay-value="${interval}"
       data-polling-max-polls-value="3" data-last-event-id="old-event">
    <span data-polling-target="content" data-key="feed.refreshing">Refreshing feed</span>
    <span hidden data-polling-target="timeoutMessage" data-key="feed.refresh-notice">Reload to check progress</span>
  </div>`

beforeEach(async () => {
  dom = new JSDOM('<div data-key="feed.refresh-status"></div><div data-key="feed.activity"></div>', { url: "http://localhost" })
  const { window } = dom
  Object.assign(globalThis, {
    window, document: window.document, MutationObserver: window.MutationObserver,
    Node: window.Node, Element: window.Element, HTMLElement: window.HTMLElement
  })
  requests = []
  respond = async () => new Response("")
  mock.method(globalThis, "fetch", async (url, options) => {
    requests.push({ url: new URL(url), ...options })
    return respond(options.signal)
  })
  status = document.querySelector('[data-key="feed.refresh-status"]')
  globalThis.Turbo = { renderStreamMessage: html => { status.innerHTML = html } }
  application = Application.start()
  application.register("polling", PollingController)
  mock.method(application, "handleError", () => {})
  await settle()
  mock.timers.enable({ apis: ["setTimeout", "Date"], now: 0 })
})

afterEach(async () => {
  document.body.replaceChildren()
  await settle()
  application.stop()
  dom.window.close()
  delete globalThis.Turbo
  delete globalThis.navigator.onLine
  mock.restoreAll()
  mock.timers.reset()
})

async function start(interval) {
  status.innerHTML = markup(interval)
  await settle()
}

async function tick(milliseconds) {
  mock.timers.tick(milliseconds)
  await settle()
}

test("starts polling when refresh markup mounts and stops when completion replaces it", async () => {
  await tick(1000)
  assert.equal(requests.length, 0)
  await start()
  await tick(100)
  assert.equal(requests.length, 1)
  assert.equal(requests[0].url.searchParams.get("after_id"), "old-event")
  assert.equal(requests[0].url.searchParams.get("refresh_after"), "previous")
  respond = async () => new Response(" ")
  await tick(100)
  await tick(1000)
  assert.equal(requests.length, 2)
})

test("keeps the polling limit when activity outside the polling element changes", async () => {
  await start()
  await tick(100)
  document.querySelector('[data-key="feed.activity"]').innerHTML = "New activity"
  await tick(200)
  assert.equal(document.querySelector('[data-key="feed.refreshing"]').hidden, true)
  assert.equal(document.querySelector('[data-key="feed.refresh-notice"]').hidden, false)
  const count = requests.length
  await tick(1000)
  assert.equal(requests.length, count)
})

for (const failure of ["HTTP error", "sign-in redirect", "network error"]) {
  test(`stops polling and shows the existing fallback after ${failure}`, async () => {
    respond = async () => {
      if (failure === "network error") throw new TypeError("Connection failed")
      return { ok: failure !== "HTTP error", redirected: failure === "sign-in redirect" }
    }
    await start()
    await tick(100)
    assert.equal(document.querySelector('[data-key="feed.refreshing"]').hidden, true)
    assert.equal(document.querySelector('[data-key="feed.refresh-notice"]').hidden, false)
    await tick(1000)
    assert.equal(requests.length, 1)
  })
}

test("uses the polling budget while offline", async () => {
  Object.defineProperty(globalThis.navigator, "onLine", { configurable: true, value: false })
  await start()
  await tick(300)
  assert.equal(requests.length, 0)
  assert.equal(document.querySelector('[data-key="feed.refresh-notice"]').hidden, false)
})

test("aborts a stalled request when the polling budget expires", async () => {
  mock.timers.reset()
  respond = signal => new Promise((resolve, reject) => {
    signal.addEventListener("abort", () => reject(signal.reason))
  })
  await start(10)
  await new Promise(resolve => setTimeout(resolve, 70))
  assert.equal(requests.length, 1)
  assert.equal(requests[0].signal.aborted, true)
  assert.equal(document.querySelector('[data-key="feed.refresh-notice"]').hidden, false)
})

test("cancels polling when leaving the page", async () => {
  await start()
  await tick(100)
  status.remove()
  await settle()
  assert.equal(requests[0].signal.aborted, true)
  await tick(1000)
  assert.equal(requests.length, 1)
})
