export const HeaderScrollspyHook = {
  mounted () {
    this.callback = event => {
      if (this.el.scrollTop > 0) {
        Alpine.store('header').scrolled = true
      } else {
        Alpine.store('header').scrolled = false
      }
    }

    this.el.addEventListener('scroll', this.callback)
    window.addEventListener('phx:page-loading-stop', this.callback)
    Alpine.store('header').scrolled = false
  },

  destroyed () {
    this.el.removeEventListener('click', this.callback)
    window.removeEventListener('phx:page-loading-stop', this.callback)
    Alpine.store('header').scrolled = false
  }
}
