export const ScrollIntoViewHook = {
  mounted () {
    const chapterRows = Array.from(this.el.firstElementChild.children)
    const observerConfig = { attributes: true }
    const observer = new MutationObserver((mutationList, observer) => {
      for (const mutation of mutationList) {
        if (mutation.attributeName === 'data-active' && mutation.target.dataset.active) {
          this.scrollIntoView(mutation.target)
        }
      }
    })

    this.observer = observer

    chapterRows.forEach((row) => {
      observer.observe(row, observerConfig)
    })

    const activeRow = chapterRows.find((row) => row.dataset.active)
    if (activeRow) {
      this.scrollIntoView(activeRow)
    }
  },

  scrollIntoView(el) {
    console.log('scrolling to', el)
    el.scrollIntoView({block: 'center'})
  },

  destroyed() {
    this.observer.disconnect()
  }
}
