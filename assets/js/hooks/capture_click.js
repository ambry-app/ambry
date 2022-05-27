export const CaptureClick = {
  mounted () {
    const lvTarget = this.el.getAttribute('phx-target')
    const lvEvent = this.el.getAttribute('phx-event')
    let values = {}

    for (const attribute of this.el.attributes) {
      if(attribute.name.startsWith('phx-value-')) {
        values[attribute.name.replace('phx-value-', '')] = attribute.value
      }
    }

    this.callback = event => {
      event.preventDefault()
      event.stopPropagation()
      this.pushEventTo(lvTarget, lvEvent, values)
    }

    this.el.addEventListener('click', this.callback)
  },

  destroyed () {
    this.el.removeEventListener('click', this.callback)
  }
}
