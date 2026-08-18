// Two jobs, both of which belong to whoever knows how tall the header is.
//
// 1. The hairline under the header, drawn only once there is something above
//    the fold. This used to be mounted on `#main-content` and read
//    `this.el.scrollTop`, back when that div was a scrollport; the document
//    is the scroller now, so it watches the window. The header carries its
//    own `border-zinc-900` and this only toggles `border-b`, so the color is
//    stated once, next to the rest of the header's costume.
//
// 2. `scroll-padding-top` on the root element, so an in-page anchor
//    (`href="#unresolved"`) doesn't park its target underneath a sticky
//    header. Measured rather than guessed: the header is one row on a form
//    and three on a list, and it reflows with the window.
export const HeaderScrollspyHook = {
  mounted() {
    this.onScroll = () => this.el.classList.toggle("border-b", window.scrollY > 0)
    this.onResize = () => this.publishHeight()

    window.addEventListener("scroll", this.onScroll, { passive: true })
    window.addEventListener("phx:page-loading-stop", this.onScroll)
    window.addEventListener("resize", this.onResize)

    this.observer = new ResizeObserver(this.onResize)
    this.observer.observe(this.el)

    this.onScroll()
    this.publishHeight()
  },

  updated() {
    this.onScroll()
    this.publishHeight()
  },

  destroyed() {
    window.removeEventListener("scroll", this.onScroll)
    window.removeEventListener("phx:page-loading-stop", this.onScroll)
    window.removeEventListener("resize", this.onResize)
    this.observer.disconnect()
    document.documentElement.style.scrollPaddingTop = ""
  },

  publishHeight() {
    document.documentElement.style.scrollPaddingTop = `${this.el.offsetHeight}px`
  },
}
