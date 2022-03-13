export default () => ({
  canReadMore: false,

  expanded: false,

  init () {
    const {
      clientWidth,
      clientHeight,
      scrollWidth,
      scrollHeight
    } = this.$el.firstElementChild

    this.canReadMore = scrollHeight > clientHeight || scrollWidth > clientWidth
  },

  toggle () {
    this.expanded = !this.expanded
  }
})
