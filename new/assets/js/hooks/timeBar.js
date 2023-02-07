export const TimeBarHook = {
  mounted () {
    const {duration} = this.el.dataset

    this.duration = duration
    this.dragging = false
    this.wrapper = this.el
    this.timeCode = this.wrapper.firstElementChild
    this.timeBar = this.wrapper.lastElementChild
    this.progressBar = this.timeBar.firstElementChild
    this.handle = this.timeBar.lastElementChild
    this.fullWidth = this.wrapper.clientWidth
    this.width = this.timeBar.clientWidth

    this.progressBarHoverStyles = this.getHoverStyles(this.progressBar)
    this.handleHoverStyles = this.getHoverStyles(this.handle)

    this.attach(this.wrapper, "mousedown")
    this.attach(window, "mousemove")
    this.attach(window, "mouseup")
    this.attach(document.body, "mouseleave")
    this.attach(window, "resize")
  },

  attach(target, event) {
    const callback = (e) => this[event](e)
    target.addEventListener(event, callback)

    this.listeners = this.listeners || []
    this.listeners.push([target, event, callback])
  },

  updateState (event) {
    const x = event.clientX

    this.position = Math.min(x, this.width)
    this.ratio = this.position / this.width
    this.percent = (this.ratio * 100).toFixed(2)
  },

  snapshotState () {
    const {position, ratio, percent} = this
    this.snapshot = {position, ratio, percent}
  },

  resetToSnapshot () {
    const {position, ratio, percent} = this.snapshot
    this.position = position
    this.ratio = ratio
    this.percent = percent
  },

  updateUI () {
    if (this.isDragging()) {
      this.progressBar.style.width = `${this.percent}%`
      this.handle.style.left = `calc(${this.percent}% - 8px)`
    }

    this.timeCode.innerText = this.formatTimecode(this.ratio * this.duration)
    const timeCodeHalfWidth = this.timeCode.clientWidth / 2
    if (this.position > this.width / 2) {
      const shiftStrength = (((this.percent - 50) * -1) / 50) + 1
      const timeCodePosition = this.fullWidth - this.position - shiftStrength * timeCodeHalfWidth
      this.timeCode.style.left = "auto"
      this.timeCode.style.right = `${timeCodePosition}px`
    } else {
      const shiftStrength = this.percent / 50
      const timeCodePosition = this.position - shiftStrength * timeCodeHalfWidth
      this.timeCode.style.left = `${timeCodePosition}px`
      this.timeCode.style.right = "auto"
    }
  },

  mousedown (event) {
    if (event.buttons === 1) {
      this.snapshotState()
      this.updateState(event)
      this.startDragging()
      this.updateUI()
    }

    event.preventDefault()
  },

  mousemove (event) {
    this.updateState(event)
    this.updateUI()
  },

  mouseup (event) {
    if (this.isDragging()) {
      this.endDragging()
      mediaPlayer.seekRatio(this.ratio)
    }
  },

  mouseleave (event) {
    if (this.isDragging()) {
      this.resetToSnapshot()
      this.updateUI()
      this.endDragging()
    }
  },

  resize (event) {
    this.fullWidth = this.wrapper.clientWidth
    this.width = this.timeBar.clientWidth
  },

  startDragging () {
    this.dragging = true
    this.wrapper.setAttribute('phx-update', 'ignore')
    this.progressBar.classList.add(...this.progressBarHoverStyles)
    this.handle.classList.add(...this.handleHoverStyles)
  },

  endDragging () {
    this.dragging = false
    this.wrapper.removeAttribute('phx-update')
    this.progressBar.classList.remove(...this.progressBarHoverStyles)
    this.handle.classList.remove(...this.handleHoverStyles)
  },

  isDragging () {
    return this.dragging
  },

  getHoverStyles (el) {
    return Array.from(el.classList)
      .filter((c) => c.startsWith('group-hover:'))
      .map((c) => c.replace('group-hover:', ''))
  },

  formatTimecode (secs) {
    const sec_num = parseInt(secs, 10)
    const hours = Math.floor(sec_num / 3600)
    const minutes = Math.floor(sec_num / 60) % 60
    const seconds = sec_num % 60

    const string = [hours, minutes, seconds]
      .map(v => v < 10 ? "0" + v : v)
      .filter((v,i) => v !== "00" || i > 0)
      .join(":")

    if (string.startsWith("0")) {
      return string.slice(1)
    } else {
      return string
    }
  },

  destroyed () {
    this.listeners.forEach((listener) => {
      const [target, event, callback] = listener
      target.removeEventListener(event, callback)
    })
  }
}
