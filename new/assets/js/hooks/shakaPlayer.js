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

    // shaka event handlers
    player.addEventListener('error', event => this.onError(event))

    // audio element event handlers
    audio.addEventListener('play', () => this.playbackStarted())
    audio.addEventListener('pause', () => this.playbackPaused())
    audio.addEventListener('ended', () => this.playbackPaused())
    audio.addEventListener('ratechange', () => this.playbackRateChanged())
    audio.addEventListener('seeked', () => this.seeked())

    // LiveView event handlers
    this.el.addEventListener('ambry:toggle-playback',() => this.playPause())
    this.el.addEventListener('ambry:seek-relative',(event) => this.seekRelative(event.detail.value))

    this.audio = audio
    this.player = player
    window.mediaPlayer = this

    this.loadMediaFromDataset(dataset)
  },

  // player controls

  playPause () {
    if (this.isPaused()) {
      this.play()
    } else {
      this.pause()
    }
  },

  seek (time) {
    this.setCurrentTime(time)
  },

  seekRelative (seconds) {
    const duration = this.getDuration()

    let newTime = this.time + seconds * this.playbackRate

    newTime = newTime < 0 ? 0 : newTime
    newTime = newTime > duration ? duration : newTime

    this.time = newTime
    this.setCurrentTime(this.time)

    // pre-emptive server update for better UI experience
    this.pushEvent('playback-time-updated', { 'playback-time': newTime })
  },

  seekRatio (ratio) {
    const duration = this.getDuration()
    const newTime = duration * ratio

    this.setCurrentTime(newTime)
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

    this.pushEvent('playback-paused', { 'playback-time': this.getCurrentTime() })
  },

  playbackRateChanged () {
    const playbackRate = this.getPlaybackRate()

    if (playbackRate && playbackRate != this.playbackRate) {
      this.pushEvent('playback-rate-changed', { 'playback-rate': playbackRate })
      this.playbackRate = playbackRate
    }
  },

  seeked () {
    this.time = this.getCurrentTime()
    this.pushEvent('playback-time-updated', { 'playback-time': this.time, persist: true })
  },

  beforeUnload (e) {
    e.preventDefault()
    return ""
  },

  reloadMedia (autoplay = false) {
    const { mediaId } = this.el.dataset

    if (mediaId === this.mediaId) {
      // no change was made
      return
    }

    if (!this.isPaused()) {
      this.audio.addEventListener(
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
    const time = parseFloat(mediaPosition)

    this.mediaId = mediaId
    this.playbackRate = mediaPlaybackRate
    this.loaded = true

    try {
      await player.load(mediaPath, time)
      this.setPlaybackRate(parseFloat(mediaPlaybackRate))

      console.log('Shaka: Media loaded')

      if (autoplay) {
        this.play()
      }
    } catch (e) {
      this.onError(e)
      return
    }
  },

  // Audio element interface

  play () {
    this.audio.play()
  },

  pause () {
    this.audio.pause()
  },

  setCurrentTime (time) {
    this.audio.currentTime = time
  },

  getCurrentTime () {
    return this.audio.currentTime
  },

  setPlaybackRate (rate) {
    this.audio.playbackRate = rate
  },

  getPlaybackRate () {
    return this.audio.playbackRate
  },

  getDuration () {
    return this.audio.duration
  },

  isPaused () {
    return this.audio.paused
  },

  // Helpers

  setPersistInterval () {
    this.interval = window.setInterval(() => {
      this.pushEvent('playback-time-updated', { 'playback-time': this.getCurrentTime(), persist: true })
    }, 60000)
  },

  clearPersistInterval () {
    window.clearInterval(this.interval)
  },

  setUpdateInterval () {
    this.interval = window.setInterval(() => {
      this.pushEvent('playback-time-updated', { 'playback-time': this.getCurrentTime() })
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
