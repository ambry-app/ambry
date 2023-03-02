export const MainTainAttrsHook = {
  attrs(){ return this.el.getAttribute("data-attrs").split(", ") },
  beforeUpdate(){ this.prevAttrs = this.attrs().map(name => [name, this.el.getAttribute(name)]) },
  updated(){ this.prevAttrs.forEach(([name, val]) => this.el.setAttribute(name, val)) }
}
