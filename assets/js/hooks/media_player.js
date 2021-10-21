import { MediaPlayer } from 'dashjs'

export const MediaPlayerHook = {
  mounted () {
    const [audio] = this.el.getElementsByTagName('audio')
    const { mediaId, mediaPath } = this.el.dataset
    const player = MediaPlayer().create()

    player.initialize(audio, mediaPath, false)
    player.on(MediaPlayer.events.CAN_PLAY, () => this.canPlay())

    this.handleEvent('reload-media', opts => {
      this.reloadMedia(opts)
    })

    this.handleEvent('play', () => {
      this.play()
    })

    this.handleEvent('pause', () => {
      this.pause()
    })

    this.mediaId = mediaId
    this.player = player
    window.mediaPlayer = this
  },

  updated () {
    // console.log('updated')
  },

  // player controls

  play () {
    this.player.play()
  },

  pause () {
    this.player.pause()
  },

  playPause () {
    if (this.player.isReady()) {
      if (this.player.isPaused()) {
        this.play()
      } else {
        this.pause()
      }
    }
  },

  seekRelative (seconds) {
    const player = this.player
    const duration = player.duration()

    let position = player.time() + seconds * player.getPlaybackRate()

    position = position < 0 ? 0 : position
    position = position > duration ? duration : position

    player.seek(position)
  },

  seekRatio (ratio) {
    const player = this.player
    player.seek(player.duration() * ratio)
  },

  setPlaybackRate (rate) {
    const player = this.player
    player.setPlaybackRate(rate)
  },

  // events from Dash.js

  canPlay (opts = {}) {
    const player = this.player
    const { mediaPlaybackRate } = this.el.dataset

    player.setPlaybackRate(parseFloat(mediaPlaybackRate))

    if (!this.handlersAttached) {
      player.on(MediaPlayer.events.PLAYBACK_PLAYING, () =>
        this.playbackStarted()
      )
      player.on(MediaPlayer.events.PLAYBACK_PAUSED, () => this.playbackPaused())
      player.on(MediaPlayer.events.PLAYBACK_RATE_CHANGED, () =>
        this.playbackRateChanged()
      )
      player.on(MediaPlayer.events.PLAYBACK_TIME_UPDATED, () =>
        this.playbackTimeUpdated()
      )

      this.handlersAttached = true
    }

    this.pushEvent('duration-loaded', { duration: player.duration() })

    if (opts.play) {
      // WARNING: mutating opts state so that the next time this callback fires
      // it doesn't auto-play. It's only meant to auto-play the FIRST time it
      // fires.
      opts.play = false
      this.play()
    }
  },

  playbackStarted () {
    this.pushEvent('playback-started')
  },

  playbackPaused () {
    const time = this.player.time()
    this.pushEvent('playback-paused', { 'playback-time': time })
  },

  playbackRateChanged () {
    const playbackRate = this.player.getPlaybackRate()
    this.pushEvent('playback-rate-changed', { 'playback-rate': playbackRate })
  },

  playbackTimeUpdated () {
    const time = this.player.time()
    this.pushEvent('playback-time-updated', { 'playback-time': time })
  },

  reloadMedia (opts) {
    const player = this.player
    const { mediaId, mediaPath } = this.el.dataset

    if (this.player.isReady()) {
      this.pause()
    }

    // wait a bit so that the pause action can take effect
    window.setImmediate(() => {
      player.attachSource(mediaPath)

      player.on(MediaPlayer.events.CAN_PLAY, () => this.canPlay(opts))

      this.mediaId = mediaId
    })
  },

  loadAndPlayMedia (mediaId) {
    this.pushEvent('load-and-play-media', { 'media-id': mediaId })
  }
}
