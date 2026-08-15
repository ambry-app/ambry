// Clears a flash after its own timeout.
//
// It runs the element's `phx-click` rather than re-implementing the dismissal:
// that attribute already holds `JS.push("lv:clear-flash") |> hide(...)`, so
// timing out and clicking are the same thing by construction and cannot drift
// apart. Clearing the flash server-side matters as much as hiding it — a flash
// left in the session reappears on the next navigation.
//
// Hovering holds it open. A message that vanishes mid-sentence is the
// complaint that replaces "they never go away", and the timer restarts on
// leave rather than resuming, because the reason you hovered is that you had
// not finished reading.
export const AutoDismissHook = {
  mounted() {
    this.after = parseInt(this.el.dataset.dismissAfter, 10)

    if (!this.after) return

    this.start()
    this.attach("mouseenter", () => this.stop())
    this.attach("focusin", () => this.stop())
    this.attach("mouseleave", () => this.start())
    this.attach("focusout", () => this.start())
  },

  start() {
    this.stop()
    this.timer = setTimeout(() => this.dismiss(), this.after)
  },

  stop() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  },

  dismiss() {
    this.liveSocket.execJS(this.el, this.el.getAttribute("phx-click"))
  },

  attach(event, callback) {
    this.el.addEventListener(event, callback)

    this.listeners = this.listeners || []
    this.listeners.push([event, callback])
  },

  destroyed() {
    this.stop()
    ;(this.listeners || []).forEach(([event, callback]) => {
      this.el.removeEventListener(event, callback)
    })
  },
}
