import assert from "node:assert/strict"
import { afterEach, beforeEach, mock, test } from "node:test"
import { JSDOM } from "jsdom"
import { Application } from "@hotwired/stimulus"
import FeedRefreshController from "controllers/feed_refresh_controller"

let dom, application, host, activity, notice, requests, respond
const progress = cursor => `<span data-feed-refresh-target="progress" data-refresh-after="${cursor}">Refreshing feed</span>`
const settle = () => new Promise(resolve => setImmediate(resolve))

beforeEach(async () => {
  dom = new JSDOM(`
    <div data-controller="feed-refresh" data-feed-refresh-endpoint-value="/feeds/123.turbo_stream">
      <div id="status"></div>
      <p hidden data-feed-refresh-target="notice"></p>
      <div data-feed-refresh-target="activity" data-last-event-id="old-event"></div>
    </div>
  `, { url: "http://localhost" })
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
  globalThis.Turbo = {
    renderStreamMessage: html => {
      document.querySelector("#status").innerHTML = html
    }
  }
  host = document.querySelector('[data-controller="feed-refresh"]')
  activity = document.querySelector('[data-feed-refresh-target="activity"]')
  notice = document.querySelector('[data-feed-refresh-target="notice"]')
  application = Application.start()
  application.register("feed-refresh", FeedRefreshController)
  await settle()
  mock.timers.enable({ apis: ["setTimeout"] })
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

async function start(cursor = "previous-refresh") {
  document.querySelector("#status").innerHTML = progress(cursor)
  await settle()
}

async function tick(milliseconds) {
  mock.timers.tick(milliseconds)
  await settle()
}

test("polls only after a refresh starts and stops when its spinner is removed", async () => {
  await tick(10000)
  assert.equal(requests.length, 0)
  await start()
  await tick(4999)
  assert.equal(requests.length, 0)
  await tick(1)
  assert.equal(requests.length, 1)
  assert.equal(requests[0].url.searchParams.get("refresh_after"), "previous-refresh")
  assert.equal(requests[0].url.searchParams.get("after_id"), "old-event")

  respond = async () => new Response('<span data-key="refresh-result">Done</span>')
  await tick(5000)
  assert.equal(requests.length, 2)
  await tick(300000)
  assert.equal(requests.length, 2)
  assert.equal(notice.hidden, true)
})

test("resumes polling an in-progress refresh on page load", async () => {
  host.removeAttribute("data-controller")
  await settle()
  document.querySelector("#status").innerHTML = progress("started-event")
  host.setAttribute("data-controller", "feed-refresh")
  await settle()
  await tick(5000)
  assert.equal(requests.length, 1)
  assert.equal(requests[0].url.searchParams.get("refresh_after"), "started-event")
})

test("keeps the deadline across activity and spinner replacements", async () => {
  await start()
  await tick(240000)
  activity.outerHTML = '<div data-feed-refresh-target="activity" data-last-event-id="new-event"></div>'
  await start("started-event")
  await tick(5000)
  assert.equal(requests.at(-1).url.searchParams.get("after_id"), "new-event")
  assert.equal(requests.at(-1).url.searchParams.get("refresh_after"), "started-event")
  await tick(55000)
  assert.equal(notice.hidden, false)
  assert.match(notice.textContent, /longer than expected/)
  assert.equal(document.querySelector('[data-feed-refresh-target="progress"]').hidden, true)
  const count = requests.length
  await tick(300000)
  assert.equal(requests.length, count)
})

for (const failure of ["HTTP error", "sign-in redirect", "network error"]) {
  test(`stops polling and clears progress after a ${failure}`, async () => {
    respond = async () => {
      if (failure === "network error") throw new TypeError("Connection failed")
      return { ok: failure !== "HTTP error", redirected: failure === "sign-in redirect" }
    }
    await start()
    await tick(5000)
    assert.equal(requests.length, 1)
    assert.equal(notice.hidden, false)
    assert.match(notice.textContent, /Couldn't check the refresh/)
    assert.equal(document.querySelector('[data-feed-refresh-target="progress"]').hidden, true)
    await tick(300000)
    assert.equal(requests.length, 1)
  })
}

test("aborts a stalled request at the deadline and permits a new refresh", async () => {
  respond = signal => new Promise((resolve, reject) => {
    signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")))
  })
  await start()
  await tick(5000)
  await tick(295000)
  assert.equal(requests.length, 1)
  assert.equal(requests[0].signal.aborted, true)
  assert.equal(notice.hidden, false)
  assert.match(notice.textContent, /longer than expected/)

  respond = async () => new Response("")
  await start("another-refresh")
  assert.equal(notice.hidden, true)
  await tick(5000)
  assert.equal(requests.length, 2)
})

test("times out even while offline", async () => {
  Object.defineProperty(globalThis.navigator, "onLine", { configurable: true, value: false })
  await start()
  await tick(300000)
  assert.equal(requests.length, 0)
  assert.equal(notice.hidden, false)
  assert.match(notice.textContent, /longer than expected/)
})

test("cancels requests and timers when leaving the page", async () => {
  await start()
  await tick(5000)
  host.remove()
  await settle()
  assert.equal(requests[0].signal.aborted, true)
  await tick(300000)
  assert.equal(requests.length, 1)
  assert.equal(notice.hidden, true)
})

test("does not poll a Turbo cached preview", async () => {
  document.documentElement.setAttribute("data-turbo-preview", "")
  await start()
  await tick(300000)
  assert.equal(requests.length, 0)
})
