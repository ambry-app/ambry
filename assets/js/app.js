// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "./vendor/some-package.js"
//
// Alternatively, you can `npm install some-package` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import 'phoenix_html'
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import topbar from '../vendor/topbar'
import Alpine from 'alpinejs'
import { ShakaPlayerHook } from './hooks/shaka_player'
import { HeaderScrollspyHook } from './hooks/header_scrollspy'
import readMore from './alpine/read_more'
import player from './alpine/player'

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content')

const liveSocket = new LiveSocket('/live', Socket, {
  params: { _csrf_token: csrfToken },
  hooks: {
    mediaPlayer: ShakaPlayerHook,
    headerScrollspy: HeaderScrollspyHook
  },
  dom: {
    onBeforeElUpdated (from, to) {
      if (from._x_dataStack) {
        Alpine.clone(from, to)
      }
    }
  }
})

const dark = localStorage.theme === 'dark' || (!('theme' in localStorage) && window.matchMedia('(prefers-color-scheme: dark)').matches)

window.formatTimecode = (secs) => {
  const sec_num = parseInt(secs, 10)
  const hours = Math.floor(sec_num / 3600)
  const minutes = Math.floor(sec_num / 60) % 60
  const seconds = sec_num % 60

  const string = [hours, minutes, seconds]
    .map(v => v < 10 ? "0" + v : v)
    .filter((v,i) => v !== "00" || i > 0)
    .join(":")

  if (string.startsWith("0")) {
    return string.slice(1)
  } else {
    return string
  }
}

window.formatDecimal = (num) => {
  const formatted = parseFloat(num).toFixed(2)

  if (/\d+\.\d0/.test(formatted)) {
    return formatted.slice(0, -1)
  } else {
    return formatted
  }
}

// Setup Alpine.js
window.Alpine = Alpine

Alpine.data('readMore', readMore)
Alpine.store('header', { scrolled: false })
Alpine.store('search', { open: false, query: "" })
Alpine.store('player', player)
Alpine.start()

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: dark ? '#A3E635' : '#84CC16' }, shadowColor: 'rgba(0, 0, 0, .3)' })
window.addEventListener('phx:page-loading-start', info => topbar.show())
window.addEventListener('phx:page-loading-stop', info => topbar.hide())

// autofocus hack:
window.addEventListener('phx:page-loading-stop', info => {
  const autoFocusElements = document.querySelectorAll('[phx-autofocus]')
  const els = autoFocusElements.length

  if (els >= 1) { window.setTimeout(() => autoFocusElements[0].focus(), 0) }
  if (els > 1) { console.warn("Multiple autofocus elements found. Only focusing the first.") }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
