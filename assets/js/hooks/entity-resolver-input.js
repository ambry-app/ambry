// Tells the surrounding form that an EntityResolver's hidden inputs moved.
//
// The resolver handles every interaction server-side (`phx-target={@myself}`),
// so the form has to be told separately that the answer changed. The server
// says so by pushing `entity-resolver:moved` with the answer in it, and this
// writes it into the hidden inputs and fires the `input` event a native
// control would have fired.
//
// **The values come from the event rather than being read off the DOM.** A
// `phx-change` in flight locks a form's inputs, and typing in the resolver
// starts one on every keystroke, so the patch carrying a pick can still be
// unwritten when this runs. Reading the DOM there submits the previous
// answer; the payload is authoritative.
//
// It replaces a MutationObserver on the value attribute, which fired on any
// change including the ones the server made for reasons of its own — so
// re-rendering a row around a different record was reported to the form as an
// operator edit.
export const EntityResolverInputHook = {
  mounted() {
    // Events reach every hook handling this name, so each one has to
    // recognise its own resolver.
    this.handleEvent("entity-resolver:moved", ({ id, value, text }) => {
      if (id !== this.el.dataset.resolver) return

      this.el.value = value

      if (text !== null && text !== undefined) {
        const textInput = document.getElementById(`${id}-text`)
        if (textInput) textInput.value = text
      }

      // One dispatch, not one per input: firing `input` anywhere in a form
      // makes LiveView serialize the whole form, so a second would be a
      // second identical round trip.
      this.el.dispatchEvent(new Event("input", { bubbles: true }))
    })
  },
}
