// Keyboard support for the entity-resolver combobox: arrows move the active
// option, Enter picks it, Escape closes. The options are LiveView-rendered
// `[role=option]` elements with phx-click, so "pick" is just a click.
export const ComboboxNavHook = {
  mounted() {
    this.input = this.el.querySelector("[role=combobox]")

    this.onKeydown = (event) => {
      const options = Array.from(this.el.querySelectorAll("[role=option]"))
      if (options.length === 0 && event.key !== "Escape") return

      switch (event.key) {
        case "ArrowDown":
        case "ArrowUp": {
          event.preventDefault()
          const delta = event.key === "ArrowDown" ? 1 : -1
          const current = options.findIndex((el) => el.hasAttribute("data-active"))
          const next = (current + delta + options.length) % options.length
          options.forEach((el) => el.removeAttribute("data-active"))
          options[next].setAttribute("data-active", "")
          options[next].scrollIntoView({ block: "nearest" })
          this.input.setAttribute("aria-activedescendant", options[next].id)
          break
        }
        case "Enter": {
          const active = options.find((el) => el.hasAttribute("data-active"))
          if (active) {
            event.preventDefault()
            active.click()
          }
          break
        }
        case "Escape": {
          this.pushEventTo(this.el, "close", {})
          break
        }
      }
    }

    this.input?.addEventListener("keydown", this.onKeydown)
  },

  destroyed() {
    this.input?.removeEventListener("keydown", this.onKeydown)
  },
}
