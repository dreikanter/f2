import { execFileSync } from "node:child_process"
import { registerHooks } from "node:module"
import { pathToFileURL } from "node:url"

const gemPath = execFileSync("bundle", ["show", "stimulus-rails"], { encoding: "utf8" }).trim()
const stimulus = pathToFileURL(`${gemPath}/app/assets/javascripts/stimulus.min.js`).href

// Match config/importmap.rb, including the exact asset served by stimulus-rails.
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "@hotwired/stimulus") {
      return { url: stimulus, format: "module", shortCircuit: true }
    }
    if (specifier.startsWith("controllers/")) {
      return {
        url: new URL(`../../../app/javascript/${specifier}.js`, import.meta.url).href,
        format: "module", shortCircuit: true
      }
    }
    return nextResolve(specifier, context)
  }
})
