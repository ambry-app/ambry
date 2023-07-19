export const ScrollMatchHook = {
  mounted() {
    const { target: targetId } = this.el.dataset
    const target = document.getElementById(targetId)

    target.addEventListener("scroll", (event) => {
      const percentScrolled = target.scrollTop / (target.scrollHeight - target.offsetHeight)
      this.el.scrollTop = percentScrolled * (this.el.scrollHeight - this.el.offsetHeight)
    })
  },
}
