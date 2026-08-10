// Either every chip fits on one line, or every chip gets its own line.
//
// Flow layout has no native way to say this: flex-wrap happily breaks just
// the last chip onto a second line, and the CSS-only "switcher" trick keys
// off a fixed container width and force-stretches children to equal widths,
// which is wrong for content-sized pills whose count varies per row. So the
// container is measured — the sum of the chips' natural widths plus gaps
// against the container — and committed to one of exactly two modes.
//
// The measurement never uses nowrap: in a nowrap flex row the chips would
// shrink to their min-content before overflowing, hiding the overflow the
// test is looking for. In both wrap and column modes a chip's laid-out
// width IS its natural width (capped by max-w-full, which only kicks in
// when it genuinely wouldn't fit anyway).
export const FitOrStackHook = {
  mounted() {
    this.observer = new ResizeObserver(() => this.apply())
    this.observer.observe(this.el)
    this.apply()
  },
  updated() {
    // A LiveView patch may swap the chip set and re-writes the class list.
    this.apply()
  },
  destroyed() {
    this.observer.disconnect()
  },
  apply() {
    const el = this.el
    const gap = parseFloat(getComputedStyle(el).columnGap) || 0
    const kids = [...el.children]
    const natural =
      kids.reduce((sum, kid) => sum + kid.getBoundingClientRect().width, 0) +
      gap * Math.max(0, kids.length - 1)
    const fits = natural <= el.getBoundingClientRect().width + 1

    el.classList.toggle("flex-wrap", fits)
    el.classList.toggle("items-center", fits)
    el.classList.toggle("flex-col", !fits)
    el.classList.toggle("items-start", !fits)
  },
}
