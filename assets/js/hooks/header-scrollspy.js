export const HeaderScrollspyHook = {
  mounted() {
    this.navHeader = document.getElementById("nav-header")

    this.callback = (event) => {
      if (this.el.scrollTop > 0) {
        this.scrolled()
      } else {
        this.notScrolled()
      }
    }

    this.el.addEventListener("scroll", this.callback)
    window.addEventListener("phx:page-loading-stop", this.callback)
    this.notScrolled()
  },

  destroyed() {
    this.el.removeEventListener("click", this.callback)
    window.removeEventListener("phx:page-loading-stop", this.callback)
    this.notScrolled()
  },

  scrolled() {
    this.navHeader.classList.add("border-b")
  },

  notScrolled() {
    this.navHeader.classList.remove("border-b")
  },
}
