// Moving one row of an ordered has_many up or down, the way LiveView's
// `inputs_for` docs move rows: the client edits the form's own inputs and
// dispatches a change, and the server does nothing but cast the params it is
// given.
//
// Two hidden inputs per row carry everything:
//
//   <input name="book[book_authors_sort][]" value="0">      which slot goes here
//   <input name="book[book_authors][0][position]" value="0"> what to write down
//
// The sort list is read in DOM order, so swapping two of its *values* swaps
// the rows. The positions swap with them, and that half is not optional: a
// `has_many` is not order-tracked by Ecto (`Ecto.Association.Has` has no
// `:ordered` field, while `Ecto.Embedded` does), so a reorder that changes no
// field at all leaves every child changeset empty and the whole association
// is skipped — buttons that visibly work and save nothing.
//
// A row removed with the ✕ is not rendered, so it posts nothing and is not
// here to be moved; Ecto's own `sort -- drop` reconciles the two whenever
// they do arrive together. That is the whole reason this lives here rather
// than in an event handler rewriting params behind the cast: the delete and
// the move were two mechanisms indexing one list, and a move after a delete
// used to redirect the delete onto a different row.
export const ReorderRowsHook = {
  mounted() {
    this.el.addEventListener("click", (event) => {
      const button = event.target.closest("[data-move]")

      if (button && !button.disabled && this.el.contains(button)) {
        this.move(button)
      }
    })
  },

  move(button) {
    const field = button.dataset.moveField
    const from = parseInt(button.dataset.moveIndex, 10)
    const to = from + (button.dataset.move === "up" ? -1 : 1)

    const slots = Array.from(this.el.querySelectorAll(`input[name$="[${field}_sort][]"]`))
    const fromSlot = slots[from]
    const toSlot = slots[to]

    // The ends of the list wear disabled buttons; a stale page can still get
    // here, and there is nothing past the end to swap with.
    if (!fromSlot || !toSlot || to < 0) return

    const prefix = fromSlot.name.replace(`[${field}_sort][]`, "")
    const position = (key) => this.el.querySelector(`input[name="${prefix}[${field}][${key}][position]"]`)

    const fromPosition = position(fromSlot.value)
    const toPosition = position(toSlot.value)

    swapValues(fromSlot, toSlot)
    if (fromPosition && toPosition) swapValues(fromPosition, toPosition)

    button.dispatchEvent(new Event("change", { bubbles: true }))
  },
}

function swapValues(a, b) {
  const value = a.value
  a.value = b.value
  b.value = value
}
