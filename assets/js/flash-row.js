// The one flash: a brand ring drawn on a row, faded out once.
//
// Driven by the Web Animations API rather than a CSS class, because a class a
// hook adds is not in the HTML the server renders. morphdom takes it back off
// on the very next patch — and on a list that subscribes to CRUD messages,
// that patch is routinely the save's own broadcast landing mid-flash. An
// animation belongs to the element, which morphdom keeps.
const DURATION = 1600

export function flashRow(el) {
  const color = getComputedStyle(document.documentElement)
    .getPropertyValue("--row-flash-ring")
    .trim()

  // A second flash at the same target restarts it rather than layering.
  el.ambryFlash?.cancel()

  el.ambryFlash = el.animate(
    [
      { boxShadow: `inset 0 0 0 2px ${color}` },
      { boxShadow: "inset 0 0 0 2px transparent" },
    ],
    { duration: DURATION, easing: "ease-out" },
  )
}
