export const SpeedSliderHook = {
  mounted () {
    const slider = this.el

    slider.addEventListener('input', () => {
      const speed = slider.value

      window.mediaPlayer.setPlaybackRate(speed)
    })
  }
}
