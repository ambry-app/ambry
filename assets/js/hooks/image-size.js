// The caption under an image preview: how big the image actually is.
//
// **Measured from `data-measure`, not from what is on screen.** A form may
// render a derived thumbnail and zoom to the original — the audiobook form
// does — and reading the rendered element there reports the thumbnail's size,
// which is a fact about our own resizing rather than about the picture. When
// the two are the same URL the browser has it cached and nothing is fetched
// twice.
export const ImageSizeHook = {
  mounted() {
    this.preview = document.getElementById(this.el.dataset.target)
    this.measure()

    // The src changes as chips are picked, and the caption has to follow.
    this.observer = new MutationObserver((changes) => {
      if (changes.some((change) => change.attributeName === "src")) this.measure()
    })

    if (this.preview) this.observer.observe(this.preview, { attributes: true })
  },

  destroyed() {
    if (this.observer) this.observer.disconnect()
  },

  measure() {
    const src = this.el.dataset.measure || (this.preview && this.preview.src)

    if (!src) return

    const probe = new Image()

    probe.addEventListener("load", () => {
      this.el.innerText = `${probe.naturalWidth}×${probe.naturalHeight}`
    })

    // A URL that won't load says nothing rather than the last image's size.
    probe.addEventListener("error", () => {
      this.el.innerText = ""
    })

    probe.src = src
  },
}
