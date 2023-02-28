// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { ReadMoreHook } from "./hooks/readMore"
import { SearchBoxHook } from "./hooks/searchBox"
import { HeaderScrollspyHook } from "./hooks/headerScrollspy"
import { ShakaPlayerHook } from "./hooks/shakaPlayer"
import { TimeBarHook } from "./hooks/timeBar"
import { ScrollIntoViewHook } from "./hooks/scrollIntoView"

const playerId = Math.random().toString(36).substring(2,)

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket(
  "/live",
  Socket,
  {
    params: {_csrf_token: csrfToken, player_id: playerId},
    hooks: {
      readMore: ReadMoreHook,
      searchBox: SearchBoxHook,
      headerScrollspy: HeaderScrollspyHook,
      mediaPlayer: ShakaPlayerHook,
      timeBar: TimeBarHook,
      scrollIntoView: ScrollIntoViewHook
    },
  }
)

const dark = localStorage.theme === 'dark' || (!('theme' in localStorage) && window.matchMedia('(prefers-color-scheme: dark)').matches)

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: dark ? '#A3E635' : '#84CC16'}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// autofocus hack:
window.addEventListener('phx:page-loading-stop', info => {
  const autoFocusElements = document.querySelectorAll('[phx-autofocus]')
  const els = autoFocusElements.length

  if (els >= 1) { window.setTimeout(() => {
    const el = autoFocusElements[0]
    el.focus()
    el.setSelectionRange(el.value.length, el.value.length)
  }, 0) }
  if (els > 1) { console.warn("Multiple autofocus elements found. Only focusing the first.") }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

