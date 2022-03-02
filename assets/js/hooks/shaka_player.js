import shaka, { Player } from 'shaka-player'
import os from 'platform-detect/os.mjs'

// Polyfill initialization:

function initPolyfills () {
  shaka.polyfill.installAll()

  if (Player.isBrowserSupported()) {
    console.log('Shaka: Polyfills installed.')
  } else {
    // This browser does not have the minimum set of APIs we need.
    console.error('Shaka: Browser not supported!')
  }
}

document.addEventListener('DOMContentLoaded', initPolyfills)

// Shaka player hook:

export const ShakaPlayerHook = {
  async mounted () {
    const [audio] = this.el.getElementsByTagName('audio')
    const player = new Player(audio)
    const dataset = this.el.dataset
    const { mediaId, mediaPlaybackRate, mediaPosition } = dataset
    const mediaPath = os.ios ? dataset.mediaHlsPath : dataset.mediaPath
    const time = parseFloat(mediaPosition)

    // last loaded ID, rate and time
    // to know when to send updates to server
    this.mediaId = mediaId
    this.playbackRate = mediaPlaybackRate
    this.time = time

    player.addEventListener('error', event => this.onError(event))

    // audio element event handlers
    audio.addEventListener('play', () => this.playbackStarted())
    audio.addEventListener('pause', () => this.playbackPaused())
    audio.addEventListener('ratechange', () => this.playbackRateChanged())
    audio.addEventListener('timeupdate', () => this.playbackTimeUpdated())

    try {
      await player.load(mediaPath, time)
      audio.playbackRate = parseFloat(mediaPlaybackRate)
      this.alpineSetPositionAndDuration(time, audio.duration, this.playbackRate)

      console.log('Shaka: audio loaded')
    } catch (e) {
      this.onError(e)
      return
    }

    // server push event handlers
    this.handleEvent('reload-media', opts => {
      this.reloadMedia(opts)
    })

    this.handleEvent('play', () => {
      this.play()
    })

    this.handleEvent('pause', () => {
      this.pause()
    })

    this.audio = audio
    this.player = player
    window.mediaPlayer = this
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

  // event handlers

  onError (eventOrException) {
    console.error('Shaka: error:', eventOrException)
  },

  playbackStarted () {
    this.alpineSetPlaying()
    // this.pushEvent('playback-started')
  },

  playbackPaused () {
    const time = this.audio.currentTime
    this.alpineSetPaused()
    // this.pushEvent('playback-paused', { 'playback-time': time })
    this.time = time
  },

  playbackRateChanged () {
    const playbackRate = this.audio.playbackRate

    if (playbackRate && playbackRate != this.playbackRate) {
      this.alpineSetPositionAndDuration(this.audio.currentTime, this.audio.duration, playbackRate)
      // this.pushEvent('playback-rate-changed', { 'playback-rate': playbackRate })
      this.playbackRate = playbackRate
    }
  },

  playbackTimeUpdated () {
    const time = this.audio.currentTime

    if (time != this.time) {
      this.alpineSetPositionAndDuration(time, this.audio.duration, this.playbackRate)
      // this.pushEvent('playback-time-updated', { 'playback-time': time })
      this.time = time
    }
  },

  reloadMedia (opts) {
    const audio = this.audio
    const { mediaId } = this.el.dataset

    if (mediaId === this.mediaId) {
      if (opts.play) {
        // no actual change was made, so let's just play
        this.play()
      }

      return
    }

    if (!audio.paused) {
      audio.addEventListener(
        'pause',
        () => this.loadMedia(this.el.dataset, opts),
        { once: true }
      )
      this.pause()
    } else {
      this.loadMedia(this.el.dataset, opts)
    }
  },

  async loadMedia (dataset, opts = {}) {
    const { mediaId, mediaPlaybackRate, mediaPosition } = dataset
    const mediaPath = os.ios ? dataset.mediaHlsPath : dataset.mediaPath
    const player = this.player
    const audio = this.audio
    const time = parseFloat(mediaPosition)

    this.mediaId = mediaId
    this.playbackRate = mediaPlaybackRate
    this.time = time

    try {
      await player.load(mediaPath, time)
      audio.playbackRate = parseFloat(mediaPlaybackRate)

      console.log('Shaka: audio loaded')

      if (opts.play) {
        this.play()
      }
    } catch (e) {
      this.onError(e)
      return
    }
  },

  loadAndPlayMedia (mediaId) {
    // this.pushEvent('load-and-play-media', { 'media-id': mediaId })
  },

  // Alpine interop

  alpineSetPlaying () {
    Alpine.store('player').playing = true
  },

  alpineSetPaused () {
    Alpine.store('player').playing = false
  },

  alpineSetPositionAndDuration (time, duration, playbackRate) {
    const realTime = time / playbackRate
    const realDuration = duration / playbackRate
    const percentage = ((realTime / realDuration) * 100).toFixed(2)

    Alpine.store('player').playbackPercentage = percentage
    Alpine.store('player').duration = realDuration
    Alpine.store('player').time = realTime
  }
}
