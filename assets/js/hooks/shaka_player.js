import shaka, { Player } from 'shaka-player'

async function hello () {
  return await Promise.resolve('Hello')
}

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
    const { mediaId, mediaPath, mediaPlaybackRate } = this.el.dataset
    const [_url, timeParam] = mediaPath.split('#')
    const [_t, timeString] = timeParam.split('=')
    const time = parseFloat(timeString)
    const player = new Player(audio)

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
    // 4: HAVE_ENOUGH_DATA - Enough data is available—and the download rate is
    // high enough—that the media can be played through to the end without
    // interruption.
    if (this.audio.readyState === 4) {
      if (this.audio.paused) {
        this.play()
      } else {
        this.pause()
      }
    }
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
    this.pushEvent('playback-started')
  },

  playbackPaused () {
    const time = this.audio.currentTime
    this.pushEvent('playback-paused', { 'playback-time': time })
    this.time = time
  },

  playbackRateChanged () {
    const playbackRate = this.audio.playbackRate

    if (playbackRate && playbackRate != this.playbackRate) {
      this.pushEvent('playback-rate-changed', { 'playback-rate': playbackRate })
      this.playbackRate = playbackRate
    }
  },

  playbackTimeUpdated () {
    const time = this.audio.currentTime

    if (time && time != this.time) {
      this.pushEvent('playback-time-updated', { 'playback-time': time })
      this.time = time
    }
  },

  reloadMedia (opts) {
    const audio = this.audio
    const player = this.player
    const { mediaId, mediaPath, mediaPlaybackRate } = this.el.dataset

    if (mediaId === this.mediaId) {
      if (opts.play) {
        // no actual change was made, so let's just play
        this.play()
      }

      return
    }

    const loadNewMedia = async () => {
      const [_url, timeParam] = mediaPath.split('#')
      const [_t, timeString] = timeParam.split('=')
      const time = parseFloat(timeString)

      this.mediaId = mediaId
      this.playbackRate = mediaPlaybackRate
      this.time = time

      await player.load(mediaPath, time)
      audio.playbackRate = parseFloat(mediaPlaybackRate)
      if (opts.play) {
        this.play()
      }
    }

    if (!audio.paused) {
      audio.addEventListener('pause', () => loadNewMedia(), { once: true })
      this.pause()
    } else {
      loadNewMedia()
    }
  },

  loadAndPlayMedia (mediaId) {
    this.pushEvent('load-and-play-media', { 'media-id': mediaId })
  }
}
