import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { hooks as colocatedHooks } from "phoenix-colocated/summoner"
import topbar from "../vendor/topbar"

import * as hooks from "./hooks"
import { initModalScrollReset } from "./modal"

// ---------------------------------------------------------------------------
// Hooks
// ---------------------------------------------------------------------------

const Hooks = {
  ...colocatedHooks,
  ...hooks
}

// ---------------------------------------------------------------------------
// LiveSocket
// ---------------------------------------------------------------------------

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2_500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

// ---------------------------------------------------------------------------
// Progress bar
// ---------------------------------------------------------------------------

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

liveSocket.connect()
initModalScrollReset()

window.liveSocket = liveSocket

// ---------------------------------------------------------------------------
// Development helpers
// ---------------------------------------------------------------------------

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", (e) => { keyDown = e.key })
    window.addEventListener("keyup", () => { keyDown = null })
    window.addEventListener("click", (e) => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
