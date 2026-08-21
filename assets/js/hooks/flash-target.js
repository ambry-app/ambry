// An in-page jump that says where it landed.
//
// A person pill beside a credit is a link to that person's card further down
// the page, and a bare anchor jump drops you somewhere with no indication of
// which card was meant — the same problem coming back from a form to a list
// has, and `focus-row` already answers it there. Same answer, same class:
// scroll it into the middle and flash its outline once.
export const FlashTargetHook = {
  mounted() {
    this.el.addEventListener("click", (event) => {
      const link = event.target.closest('a[href^="#"]')

      if (!link || !this.el.contains(link)) return

      const target = document.getElementById(decodeURIComponent(link.hash.slice(1)))

      if (!target) return

      // The browser's own jump puts the target at the top edge, under the
      // header; centring it is the same placement the list gets.
      event.preventDefault()
      target.scrollIntoView({ block: "center", behavior: "smooth" })
      target.classList.remove("row-flash")
      // Restart the animation on a second click at the same target: a class
      // that is already there animates nothing.
      void target.offsetWidth
      target.classList.add("row-flash")
      target.addEventListener("animationend", () => target.classList.remove("row-flash"), {
        once: true,
      })
    })
  },
}
