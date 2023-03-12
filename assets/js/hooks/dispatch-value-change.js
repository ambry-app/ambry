export const DispatchValueChangeHook = {
  mounted() {
    this.previousValue = this.el.value

    this.observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (
          mutation.type === "attributes" &&
          mutation.attributeName === "value" &&
          this.el.value !== this.previousValue
        ) {
          this.previousValue = this.el.value
          this.el.dispatchEvent(new Event("change", { bubbles: true }))
        }
      })
    })

    this.observer.observe(this.el, { attributes: true })
  },

  destroyed() {
    this.observer.disconnect()
  },
}
