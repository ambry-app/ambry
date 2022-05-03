export const GoHomeHook = {
  mounted () {
    window.goHome = () => {
      this.pushEvent('go-home', {})
    }
  },

  destroyed () {
    delete window.goHome
  }
}
