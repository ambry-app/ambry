// The form footer is a sticky slab with square bottom corners, which is
// right whenever it is actually stuck to the bottom of the scrollport — but
// a form shorter than the window never sticks, and there the slab just sits
// mid-page wearing corners (and a floating shadow) that promise an edge that
// isn't there. CSS has no :stuck selector, so the scroller is measured: if it
// has nothing to scroll, the slab is an ordinary card and dresses like one.
export const StickyFooterHook = {
  mounted() {
    this.scroller = this.el.closest("#main-content") || document.getElementById("main-content")
    this.onResize = () => this.apply()
    window.addEventListener("resize", this.onResize)
    if (this.scroller) {
      this.observer = new ResizeObserver(() => this.apply())
      // observing the scroller's first child tracks content growing/shrinking
      this.observer.observe(this.scroller)
      if (this.scroller.firstElementChild) this.observer.observe(this.scroller.firstElementChild)
    }
    this.apply()
  },
  updated() {
    // a patch rewrites the class list
    this.apply()
  },
  destroyed() {
    window.removeEventListener("resize", this.onResize)
    if (this.observer) this.observer.disconnect()
  },
  apply() {
    if (!this.scroller) return
    const floats = this.scroller.scrollHeight <= this.scroller.clientHeight + 1

    this.el.classList.toggle("rounded-b-lg", floats)
    this.el.classList.toggle("shadow-none", floats)
  },
}
