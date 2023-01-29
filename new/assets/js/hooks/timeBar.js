export const TimeBarHook = {
  mounted () {
    this.dragging = false
    this.width = this.el.firstElementChild.clientWidth

    this.attach(this.el, "mousedown")
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

  mousedown (event) {
    if (event.buttons === 1) {
      this.dragging = true
    }

    event.preventDefault()
  },

  mousemove (event) {
    const x = event.clientX

    this.position = Math.min(x, this.width)
    this.ratio = this.position / this.width
    this.percent = (this.ratio * 100).toFixed(2)
  },

  mouseup (event) {
    if (this.dragging) {
      this.dragging = false
      mediaPlayer.seekRatio(this.ratio)
    }
  },

  resize (event) {
    this.width = this.el.firstElementChild.clientWidth
  },

  destroyed () {
    this.listeners.forEach((listener) => {
      const [target, event, callback] = listener
      target.removeEventListener(event, callback)
    })
  }
}
