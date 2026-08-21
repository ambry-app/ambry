// A chip that fills in one of the form's own inputs, the way LiveView's
// `inputs_for` docs move a row: the client edits the input and dispatches a
// change, and the server does nothing but cast the params it is given.
//
//   <button data-set-input="book[book_authors][0][author][author_people][0][person][description]"
//           data-set-value="Andy Weir is an American novelist…">
//
// This is what lets a photo or a biography be proposed for a person who does
// not exist yet. The alternative — an event carrying the row's index, and a
// handler reaching into the form's params to write at that path — has to
// know the shape of a nested cast_assoc chain and has to get the index right
// on a list the operator is adding to, dropping from and reordering. There
// is no index here at all: the input's name IS the path, rendered by the same
// `inputs_for` that will parse it back.
export const SetInputHook = {
  mounted() {
    this.el.addEventListener("click", (event) => {
      const chip = event.target.closest("[data-set-input]")

      if (chip && this.el.contains(chip)) {
        this.set(chip)
      }
    })
  },

  set(chip) {
    const form = this.el.closest("form")
    if (!form) return

    // `data-set-blank` is a JSON array of names to empty, for a control whose
    // answer is "none of these" and therefore touches more than one field.
    // One control, one answer, however many inputs carry it.
    const blanks = chip.dataset.setBlank ? JSON.parse(chip.dataset.setBlank) : []
    const pairs = chip.dataset.setInput
      ? [[chip.dataset.setInput, chip.dataset.setValue || ""]]
      : blanks.map((name) => [name, ""])

    // Names carry brackets, which need no escaping inside a quoted attribute
    // selector — and CSS.escape, which is for identifiers, would break them.
    const written = pairs
      .map(([name, value]) => {
        const input = form.querySelector(`[name="${name}"]`)
        if (input) input.value = value
        return input
      })
      .filter(Boolean)

    // One dispatch however many were written: `phx-change` serializes the
    // whole form, so a second is a second identical round trip. `input`, not
    // `change`: a textarea's phx-change fires on input, and a hidden input has
    // no native event of its own to borrow.
    written[written.length - 1]?.dispatchEvent(new Event("input", { bubbles: true }))
  },
}
