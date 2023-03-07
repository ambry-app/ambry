export const ReadMoreHook = {
  mounted () {
    const descriptionEl = this.el.firstElementChild
    const {
      clientWidth,
      clientHeight,
      scrollWidth,
      scrollHeight
    } = descriptionEl

    const {readMoreLabel, readLessLabel, readMoreClasses} = this.el.dataset
    const link = this.el.lastElementChild.firstElementChild
    const fadeEl = descriptionEl.lastElementChild

    this.descriptionEl = descriptionEl
    this.expanded = false
    this.classes = readMoreClasses.split(" ")
    this.link = link
    this.labels = {readMoreLabel, readLessLabel}
    this.canReadMore = scrollHeight > clientHeight || scrollWidth > clientWidth
    this.fadeEl = fadeEl

    this.callback = _event => {
      this.expanded = !this.expanded
      this.toggleReadMore()
    }

    this.link.addEventListener('click', this.callback)

    this.toggleReadMore()
  },

  toggleReadMore () {
    if (this.canReadMore && this.expanded) {
      this.fadeEl.classList.add('hidden')
      this.descriptionEl.classList.remove(...this.classes)
      this.link.innerText = this.labels.readLessLabel
    } else if (this.canReadMore && !this.expanded) {
      this.fadeEl.classList.remove('hidden')
      this.descriptionEl.classList.add(...this.classes)
      this.link.innerText = this.labels.readMoreLabel
    }
  },

  destroyed () {
    this.link.removeEventListener('click', this.callback)
  }
}
