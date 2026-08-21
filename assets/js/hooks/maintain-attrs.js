export const MainTainAttrsHook = {
  attrs() {
    return this.el.getAttribute("data-attrs").split(", ")
  },

  beforeUpdate() {
    this.prevAttrs = this.attrs().map((name) => [name, this.el.getAttribute(name)])
  },

  updated() {
    // Guarded because `updated` without a preceding `beforeUpdate` is
    // reachable — a patch that moves this element rather than updating it in
    // place mounts the hook and then updates it — and an exception thrown
    // here takes down the rest of the patch's hook callbacks with it. Losing
    // a resized textarea's height is a smaller loss than that.
    ;(this.prevAttrs || []).forEach(([name, val]) => this.el.setAttribute(name, val))
  },
}
