import shaka, { Player } from 'shaka-player'
import os from 'platform-detect/os.mjs'

// Polyfill initialization:

function initPolyfills () {
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

export const ShakaPlayerHook = {
  async mounted () {
    console.log('Shaka: Mounting...')

    const [audio] = this.el.getElementsByTagName('audio')
    const player = new Player(audio)
    const dataset = this.el.dataset

    player.addEventListener('error', event => this.onError(event))

    // audio element event handlers
    audio.addEventListener('play', () => this.playbackStarted())
    audio.addEventListener('pause', () => this.playbackPaused())
    audio.addEventListener('ended', () => this.playbackPaused())
    audio.addEventListener('ratechange', () => this.playbackRateChanged())
    audio.addEventListener('timeupdate', () => this.playbackTimeUpdated())
    audio.addEventListener('seeked', () => this.seeked())

    this.audio = audio
    this.player = player
    window.mediaPlayer = this

    this.loadMediaFromDataset(dataset)
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
    const audio = this.audio
    audio.currentTime = position
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
    const audio = this.audio
    audio.playbackRate = rate
  },

  loadAndPlayMedia (mediaId) {
    this.pushEvent('playback-time-updated', { 'playback-time': this.audio.currentTime })
    this.pushEvent('load-media', { 'media-id': mediaId }, () => {
      this.reloadMedia(true)
    })
  },

  // event handlers

  onError (eventOrException) {
    console.error('Shaka: Error:', eventOrException)
  },

  playbackStarted () {
    this.alpineSetPlaying()
    this.setSyncInterval()
    this.setUnloadHandler()
  },

  playbackPaused () {
    const time = this.audio.currentTime
    this.alpineSetPaused()
    this.pushEvent('playback-time-updated', { 'playback-time': time })
    this.time = time

    this.clearSyncInterval()
    this.clearUnloadHandler()
  },

  playbackRateChanged () {
    const playbackRate = this.audio.playbackRate

    if (playbackRate && playbackRate != this.playbackRate) {
      this.alpineSetPlaybackRate(playbackRate)
      this.pushEvent('playback-rate-changed', { 'playback-rate': playbackRate })
      this.playbackRate = playbackRate
    }
  },

  playbackTimeUpdated () {
    const time = this.audio.currentTime

    if (time != this.time) {
      this.alpineSetProgress(time)
      this.time = time
    }
  },

  seeked () {
    const time = this.audio.currentTime
    this.pushEvent('playback-time-updated', { 'playback-time': time })
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
    const { mediaId, mediaPlaybackRate, mediaPosition, mediaChapters } = dataset
    const mediaPath = os.ios ? dataset.mediaHlsPath : dataset.mediaPath
    const player = this.player
    const audio = this.audio
    const time = parseFloat(mediaPosition)
    const chapters = JSON.parse(mediaChapters).map((chapter, i) => {
      return {id: i, time: parseFloat(chapter.time), title: chapter.title}
    })

    this.mediaId = mediaId
    this.playbackRate = mediaPlaybackRate
    this.time = time

    try {
      await player.load(mediaPath, time)
      audio.playbackRate = parseFloat(mediaPlaybackRate)
      this.alpineLoadMedia(mediaId, time, audio.duration, this.playbackRate, chapters)

      console.log('Shaka: Media loaded')

      if (autoplay) {
        this.play()
      }
    } catch (e) {
      this.onError(e)
      return
    }
  },

  // Alpine interop

  alpineLoadMedia(id, time, duration, playbackRate, chapters) {
    Alpine.store('player').loadMedia(id, time, duration, playbackRate, chapters)
  },

  alpineSetPlaying() {
    Alpine.store('player').setPlaying()
  },

  alpineSetPaused() {
    Alpine.store('player').setPaused()
  },

  alpineSetProgress(time) {
    Alpine.store('player').setProgress(time)
  },

  alpineSetPlaybackRate(rate) {
    Alpine.store('player').setPlaybackRate(rate)
  },

  // Helpers

  setSyncInterval () {
    this.interval = window.setInterval(() => {
      const time = this.audio.currentTime
      this.pushEvent('playback-time-updated', { 'playback-time': time })
    }, 60000)
  },

  clearSyncInterval () {
    window.clearInterval(this.interval)
  },

  setUnloadHandler () {
    window.addEventListener("beforeunload", this.beforeUnload)
  },

  clearUnloadHandler () {
    window.removeEventListener("beforeunload", this.beforeUnload)
  }
}
