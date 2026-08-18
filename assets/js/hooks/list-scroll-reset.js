// Asking for the next page and arriving at the bottom of it is the oldest
// complaint about these lists. A page change is a `patch`, which morphs the
// DOM rather than replacing it, so the scroll offset survives untouched while
// fifty different rows appear underneath it — and the operator lands wherever
// they happened to be, which after clicking a "next" button at the foot of
// the list is the very end.
//
// Keyed on the whole list state, not just the page: changing the sort or the
// search reorders everything, and staying halfway down someone else's
// ordering is the same non-sequitur.
//
// `instant`, deliberately: this is a new page of results, not a movement
// within one, and smooth-scrolling half a screen of rows the operator never
// asked to see reads as the page fighting them.
export const ListScrollResetHook = {
  mounted() {
    this.state = this.el.dataset.listState
  },

  updated() {
    if (this.el.dataset.listState === this.state) return

    this.state = this.el.dataset.listState
    window.scrollTo({ top: 0, behavior: "instant" })
  },
}
