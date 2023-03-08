export const ScrollIntoViewHook = {
  mounted() {
    const chapterRows = Array.from(this.el.firstElementChild.children)
    const observerConfig = { attributes: true }
    const observer = new MutationObserver((mutationList, observer) => {
      for (const mutation of mutationList) {
        if (mutation.attributeName === "data-active" && mutation.target.dataset.active) {
          this.scrollIntoView(mutation.target)
        }
      }
    })

    this.chapterRows = chapterRows
    this.observer = observer

    chapterRows.forEach((row) => {
      observer.observe(row, observerConfig)
    })

    this.scrollToActive()

    this.attach(this.el, "ambry:scroll-to-active-chapter", "scrollToActive")
  },

  attach(target, event, callbackName) {
    const callback = (e) => this[callbackName || event](e)
    target.addEventListener(event, callback)

    this.listeners = this.listeners || []
    this.listeners.push([target, event, callback])
  },

  scrollIntoView(el) {
    el.scrollIntoView({ block: "center" })
  },

  scrollToActive() {
    const activeRow = this.chapterRows.find((row) => row.dataset.active)
    console.log("got it!", activeRow)

    if (activeRow) {
      requestAnimationFrame(() => {
        this.scrollIntoView(activeRow)
      })
    }
  },

  destroyed() {
    this.observer.disconnect()

    this.listeners.forEach((listener) => {
      const [target, event, callback] = listener
      target.removeEventListener(event, callback)
    })
  },
}
