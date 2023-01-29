// Polyfill initialization:

function initPolyfills () {
  const { Player } = shaka

  shaka.polyfill.installAll()

  if (Player.isBrowserSupported()) {
    console.log('Shaka: Polyfills installed')
  } else {
    // This browser does not have the minimum set of APIs we need.
    console.error('Shaka: Browser not supported!')
  }
}

document.addEventListener('DOMContentLoaded', initPolyfills)

// Shaka player hook:

// TODO: we should clean up all event listeners if the hook ever unmounts.
// This (I think) isn't currently possible, but a feature to "unload the current
// media" might eventually be implemented, in which case it will be necessary.
export const ShakaPlayerHook = {
  async mounted () {
    console.log('Shaka: Mounting...')

    const { Player } = shaka

    const [audio] = this.el.getElementsByTagName('audio')
    const player = new Player(audio)
    const dataset = this.el.dataset

    player.addEventListener('error', event => this.onError(event))

    // audio element event handlers
    audio.addEventListener('play', () => this.playbackStarted())
    audio.addEventListener('pause', () => this.playbackPaused())
    audio.addEventListener('ended', () => this.playbackPaused())
    audio.addEventListener('ratechange', () => this.playbackRateChanged())
    audio.addEventListener('seeked', () => this.seeked())

    this.audio = audio
    this.player = player
    window.mediaPlayer = this

    this.loadMediaFromDataset(dataset)

    this.el.addEventListener('ambry:toggle-playback',() => this.playPause())
    this.el.addEventListener('ambry:seek-relative',(event) => this.seekRelative(event.detail.value))
  },

  // player controls

  play () {
    this.audio.play()
  },

  pause () {
    this.audio.pause()
  },

  playPause () {
    if (this.audio.paused) {
      this.play()
    } else {
      this.pause()
    }
  },

  seek (position) {
    this.audio.currentTime = position
  },

  seekRelative (seconds) {
    const audio = this.audio
    const duration = audio.duration

    let position = audio.currentTime + seconds * audio.playbackRate

    position = position < 0 ? 0 : position
    position = position > duration ? duration : position

    audio.currentTime = position
  },

  seekRatio (ratio) {
    const audio = this.audio
    audio.currentTime = audio.duration * ratio
  },

  setPlaybackRate (rate) {
    this.audio.playbackRate = rate
  },

  loadAndPlayMedia (mediaId) {
    this.pushEvent('load-media', { 'media-id': mediaId }, () => {
      this.reloadMedia(true)
    })
  },

  // event handlers

  onError (eventOrException) {
    console.error('Shaka: Error:', eventOrException)
  },

  playbackStarted () {
    this.setPersistInterval()
    this.setUpdateInterval()
    this.setUnloadHandler()

    this.pushEvent('playback-started')
  },

  playbackPaused () {
    this.clearPersistInterval()
    this.clearUpdateInterval()
    this.clearUnloadHandler()

    this.pushEvent('playback-paused', { 'playback-time': this.audio.currentTime })
  },

  playbackRateChanged () {
    const playbackRate = this.audio.playbackRate

    if (playbackRate && playbackRate != this.playbackRate) {
      this.pushEvent('playback-rate-changed', { 'playback-rate': playbackRate })
      this.playbackRate = playbackRate
    }
  },

  seeked () {
    this.pushEvent('playback-time-updated', { 'playback-time': this.audio.currentTime, persist: true })
  },

  beforeUnload (e) {
    e.preventDefault()
    return ""
  },

  reloadMedia (autoplay = false) {
    const audio = this.audio
    const { mediaId } = this.el.dataset

    if (mediaId === this.mediaId) {
      // no change was made
      return
    }

    if (!audio.paused) {
      audio.addEventListener(
        'pause',
        () => this.loadMediaFromDataset(this.el.dataset, autoplay),
        { once: true }
      )
      this.pause()
    } else {
      this.loadMediaFromDataset(this.el.dataset, autoplay)
    }
  },

  async loadMediaFromDataset (dataset, autoplay = false) {
    if (dataset.mediaUnloaded === "") {
      console.log('Shaka: No media to load')
      this.loaded = false
      return
    }

    const { mediaId, mediaPlaybackRate, mediaPosition } = dataset
    const mediaPath = dataset.mediaPath
    const player = this.player
    const audio = this.audio
    const time = parseFloat(mediaPosition)

    this.mediaId = mediaId
    this.playbackRate = mediaPlaybackRate
    this.loaded = true

    try {
      await player.load(mediaPath, time)
      audio.playbackRate = parseFloat(mediaPlaybackRate)

      console.log('Shaka: Media loaded')

      if (autoplay) {
        this.play()
      }
    } catch (e) {
      this.onError(e)
      return
    }
  },

  // Helpers

  setPersistInterval () {
    this.interval = window.setInterval(() => {
      this.pushEvent('playback-time-updated', { 'playback-time': this.audio.currentTime, persist: true })
    }, 60000)
  },

  clearPersistInterval () {
    window.clearInterval(this.interval)
  },

  setUpdateInterval () {
    this.interval = window.setInterval(() => {
      this.pushEvent('playback-time-updated', { 'playback-time': this.audio.currentTime })
    }, 1000 / this.playbackRate)
  },

  clearUpdateInterval () {
    window.clearInterval(this.interval)
  },

  setUnloadHandler () {
    window.addEventListener("beforeunload", this.beforeUnload)
  },

  clearUnloadHandler () {
    window.removeEventListener("beforeunload", this.beforeUnload)
  }
}
