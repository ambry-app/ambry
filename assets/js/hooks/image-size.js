export const ImageSizeHook = {
  mounted() {
    const el = this.el
    const targetId = this.el.dataset.target
    const image = document.getElementById(targetId)

    const updateSize = () => {
      const size = `${image.naturalWidth}x${image.naturalHeight}`
      this.el.innerText = size
    }

    if (image.complete) {
      updateSize()
    } else {
      image.addEventListener("load", (event) => {
        updateSize()
      })
    }

    observer = new MutationObserver((changes) => {
      changes.forEach((change) => {
        if (change.attributeName.includes("src")) {
          updateSize()
        }
      })
    })
    observer.observe(image, { attributes: true })
  },
}
