// The form footer is a sticky slab with square bottom corners, which is
// right whenever it is actually stuck to the bottom of the viewport — but
// a form shorter than the window never sticks, and there the slab just sits
// mid-page wearing corners (and a floating shadow) that promise an edge that
// isn't there. CSS has no :stuck selector, so the page is measured: if it
// has nothing to scroll, the slab is an ordinary card and dresses like one.
//
// The document is the scroller, so that measurement is the document's. This
// used to measure `#main-content`, which was the scrollport until the shell
// was flattened.
export const StickyFooterHook = {
  mounted() {
    this.onResize = () => this.apply()
    window.addEventListener("resize", this.onResize)
    // The body's box tracks content growing and shrinking; the root element's
    // is what `scrollHeight` is measured against.
    this.observer = new ResizeObserver(() => this.apply())
    this.observer.observe(document.body)
    this.apply()
  },
  updated() {
    // a patch rewrites the class list
    this.apply()
  },
  destroyed() {
    window.removeEventListener("resize", this.onResize)
    this.observer.disconnect()
  },
  apply() {
    const root = document.documentElement
    const floats = root.scrollHeight <= root.clientHeight + 1

    this.el.classList.toggle("rounded-b-lg", floats)
    this.el.classList.toggle("shadow-none", floats)
  },
}
