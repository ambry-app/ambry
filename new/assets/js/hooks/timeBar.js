export const TimeBarHook = {
  mounted () {
    this.dragging = false
    this.wrapper = this.el
    this.timeBar = this.wrapper.firstElementChild
    this.progressBar = this.timeBar.firstElementChild
    this.handle = this.timeBar.lastElementChild
    this.width = this.timeBar.clientWidth

    this.attach(this.wrapper, "mousedown")
    this.attach(window, "mousemove")
    this.attach(window, "mouseup")
    this.attach(window, "resize")
  },

  attach(target, event) {
    const callback = (e) => this[event](e)
    target.addEventListener(event, callback)

    this.listeners = this.listeners || []
    this.listeners.push([target, event, callback])
  },

  updateUI () {
    this.progressBar.style.width = `${this.percent}%`
    this.handle.style.left = `calc(${this.percent}% - 8px)`
  },

  mousedown (event) {
    if (event.buttons === 1) {
      this.startDragging()
    }

    event.preventDefault()
  },

  mousemove (event) {
    const x = event.clientX

    this.position = Math.min(x, this.width)
    this.ratio = this.position / this.width
    this.percent = (this.ratio * 100).toFixed(2)

    if (this.isDragging()) {
      this.updateUI()
    }
  },

  mouseup (event) {
    if (this.isDragging()) {
      this.endDragging()
      mediaPlayer.seekRatio(this.ratio)
    }
  },

  resize (event) {
    this.width = this.timeBar.clientWidth
  },

  startDragging () {
    this.dragging = true
    this.wrapper.setAttribute('phx-update', 'ignore')
  },

  endDragging () {
    this.dragging = false
    this.wrapper.removeAttribute('phx-update')
  },

  isDragging () {
    return this.dragging
  },

  destroyed () {
    this.listeners.forEach((listener) => {
      const [target, event, callback] = listener
      target.removeEventListener(event, callback)
    })
  }
}
