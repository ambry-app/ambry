export const MediaControlsHook = {
  mounted () {
    this.setupPositionDrag()
  },

  setupPositionDrag () {
    const bar = document.getElementById('progress-bar')
    const calcRatio = event => {
      const width = bar.clientWidth
      const position = event.layerX
      let ratio = position / width

      return Math.min(Math.max(ratio, 0), 1)
    }
    let dragging = false

    bar.addEventListener('mousedown', event => {
      const ratio = calcRatio(event)

      window.mediaPlayer.seekRatio(ratio)

      dragging = true
    })
    bar.addEventListener('mousemove', event => {
      if (dragging) {
        const ratio = calcRatio(event)

        event.preventDefault()
        window.mediaPlayer.seekRatio(ratio)
      }
    })
    bar.addEventListener('mouseup', _event => {
      dragging = false
    })
  }
}
