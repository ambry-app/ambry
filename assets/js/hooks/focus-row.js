import { flashRow } from "../flash-row"

// Coming back from a form, put the operator back at the record they were
// editing rather than at the top of page one.
//
// It anchors to the record, not to a scroll offset, because those are
// different answers whenever the edit changed the sort key: rename a book
// while the list is sorted by title and its row moves, and the pixel the
// operator left from now belongs to somebody else. If the row is gone —
// deleted, or filtered out by what was just saved — nothing is lit and they
// land at the top, which is the honest result.
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

    // After paint, or the row's geometry is whatever it was mid-patch.
    if (row) {
      requestAnimationFrame(() => {
        row.scrollIntoView({ block: "center", behavior: "instant" })
        flashRow(row)
      })
    }

    this.spend()
  },

  // The address bar forgets the focus, immediately, and whether or not there
  // was a row to light up: it has been read either way, and it is in the
  // history, so an entry that keeps it lights the row up again on every back
  // and forward through it.
  //
  // Client-side, and nothing tells the server. Asking the server means a
  // `push_patch`, which costs a round trip the operator can outrun — and
  // which replaces the socket's flash with whatever that event put there
  // (`Phoenix.LiveView.Utils.changed_flash/1`), so a patch that says nothing
  // clears the "Saved." the operator is still reading.
  //
  // The entry's own state object is handed straight back, so LiveView's
  // bookkeeping for it — its type, its id, its position — is untouched and
  // only the query string moves. What LiveView does not learn is
  // `currentLocation`, which it consults on `popstate` to decide whether the
  // address really changed; it goes stale here and heals on the next
  // navigation, which is necessarily the one that happens before any pop.
  spend() {
    const url = new URL(window.location.href)

    if (!url.searchParams.has("focus")) return

    url.searchParams.delete("focus")
    history.replaceState(history.state, "", url)
  },
}
