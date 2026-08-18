// Coming back from a form, put the operator back at the record they were
// editing rather than at the top of page one.
//
// It anchors to the record, not to a scroll offset, because those are
// different answers whenever the edit changed the sort key: rename a book
// while the list is sorted by title and its row moves, and the pixel the
// operator left from now belongs to somebody else. If the row is gone —
// deleted, or filtered out by what was just saved — this does nothing and
// they land at the top, which is the honest result.
export const FocusRowHook = {
  mounted() {
    this.focus()
  },

  updated() {
    this.focus()
  },

  focus() {
    const id = this.el.dataset.focus
    // Once per arrival: a re-render (a PubSub refresh, a tick) must not drag
    // the page back to a row the operator has since scrolled away from.
    if (!id || id === this.focused) return
    this.focused = id

    const row = document.getElementById(`row-${id}`)
    if (!row) return

    // After paint, or the row's geometry is whatever it was mid-patch.
    requestAnimationFrame(() => {
      row.scrollIntoView({ block: "center", behavior: "instant" })
      row.classList.add("row-flash")
      row.addEventListener("animationend", () => row.classList.remove("row-flash"), { once: true })
    })
  },
}
