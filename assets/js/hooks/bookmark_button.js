export const BookmarkButtonHook = {
  mounted () {
    this.callback = event => {
      const position = window.mediaPlayer.audio.currentTime

      this.pushEventTo('#bookmarks-modal', 'add-bookmark', { position })
    }

    this.el.addEventListener('click', this.callback)
  },

  destroyed () {
    this.el.removeEventListener('click', this.callback)
  }
}
