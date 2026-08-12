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
import { Socket } from "phoenix"
import "phoenix_html"
import { LiveSocket } from "phoenix_live_view"
import topbar from "topbar"

import { ComboboxNavHook } from "./hooks/combobox-nav"
import { DispatchValueChangeHook } from "./hooks/dispatch-value-change"
import { FitOrStackHook } from "./hooks/fit-or-stack"
import { HeaderScrollspyHook } from "./hooks/header-scrollspy"
import { ImageSizeHook } from "./hooks/image-size"
import { InfiniteScrollHook } from "./hooks/infinite-scroll"
import { MainTainAttrsHook } from "./hooks/maintain-attrs"
import { PasteImageHook } from "./hooks/paste-image"
import { ReadMoreHook } from "./hooks/read-more"
import { ScrollIntoViewHook } from "./hooks/scroll-into-view"
import { ScrollMatchHook } from "./hooks/scroll-match"
import { SearchBoxHook } from "./hooks/search-box"
import { StickyFooterHook } from "./hooks/sticky-footer"

// Establish Phoenix Socket and LiveView configuration.
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: {
    "read-more": ReadMoreHook,
    "search-box": SearchBoxHook,
    "header-scrollspy": HeaderScrollspyHook,
    "scroll-into-view": ScrollIntoViewHook,
    "maintain-attrs": MainTainAttrsHook,
    "infinite-scroll": InfiniteScrollHook,
    "combobox-nav": ComboboxNavHook,
    "dispatch-value-change": DispatchValueChangeHook,
    "fit-or-stack": FitOrStackHook,
    "image-size": ImageSizeHook,
    "scroll-match": ScrollMatchHook,
    "paste-image": PasteImageHook,
    "sticky-footer": StickyFooterHook,
  },
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#A3E635" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300))
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide())

// autofocus hack:
window.addEventListener("phx:page-loading-stop", (info) => {
  const autoFocusElements = document.querySelectorAll("[phx-autofocus]")
  const els = autoFocusElements.length

  if (els >= 1) {
    window.setTimeout(() => {
      const el = autoFocusElements[0]
      el.focus()
      el.setSelectionRange(el.value.length, el.value.length)
    }, 0)
  }
  if (els > 1) {
    console.warn("Multiple autofocus elements found. Only focusing the first.")
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Image lightbox: any [data-zoomable] element (the corner magnifiers on
// previews, chips and record thumbnails) opens its data-full image in the
// #image-lightbox overlay. Delegated, because the elements come and go with
// LiveView patches; stopPropagation so a magnifier inside a record row's
// label or a chip's button doesn't also tick/choose.
document.addEventListener("click", (event) => {
  const box = document.getElementById("image-lightbox")
  if (!box) return

  const zoom = event.target.closest("[data-zoomable]")
  if (zoom && zoom.dataset.full) {
    event.preventDefault()
    event.stopPropagation()
    box.querySelector("img").src = zoom.dataset.full
    box.classList.remove("hidden")
    box.classList.add("flex")
  } else if (!box.classList.contains("hidden")) {
    box.classList.add("hidden")
    box.classList.remove("flex")
  }
})

window.addEventListener("keydown", (event) => {
  const box = document.getElementById("image-lightbox")
  if (event.key === "Escape" && box && !box.classList.contains("hidden")) {
    box.classList.add("hidden")
    box.classList.remove("flex")
  }
})
