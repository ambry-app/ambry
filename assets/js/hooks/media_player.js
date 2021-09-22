import { MediaPlayer } from 'dashjs'

export const MediaPlayerHook = {
  mounted () {
    const [audio] = this.el.getElementsByTagName('audio')
    const { mediaId, mediaPath } = this.el.dataset
    const player = MediaPlayer().create()

    player.initialize(audio, mediaPath, false)
    player.on(MediaPlayer.events.CAN_PLAY, () => this.canPlay())

    // this.setupPositionDrag()

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
    // Alpine.store('playerState').play(this.mediaId)
    window.mediaPlaying = this.mediaId
    this.player.play()
  },

  pause () {
    // Alpine.store('playerState').pause()
    window.mediaPlaying = null
    this.player.pause()
  },

  seekRelative (seconds) {
    const player = this.player
    player.seek(player.time() + seconds * player.getPlaybackRate())
  },

  seekRatio (ratio) {
    const player = this.player
    player.seek(player.duration() * ratio)
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
      // player.on(MediaPlayer.events.PLAYBACK_RATE_CHANGED, () =>
      //   this.playbackRateChanged()
      // )
      player.on(MediaPlayer.events.PLAYBACK_TIME_UPDATED, () =>
        this.playbackTimeUpdated()
      )

      this.handlersAttached = true
    }

    this.pushEvent('duration-loaded', { duration: player.duration() })

    if (opts.play) {
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

  // playbackRateChanged () {
  //   const playbackRate = this.player.getPlaybackRate()
  //   this.pushEvent('playback-rate-changed', { 'playback-rate': playbackRate })
  // },

  playbackTimeUpdated () {
    const time = this.player.time()
    this.pushEvent('playback-time-updated', { 'playback-time': time })
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

      this.seekRatio(ratio)

      dragging = true
    })
    bar.addEventListener('mousemove', event => {
      if (dragging) {
        const ratio = calcRatio(event)

        event.preventDefault()
        this.seekRatio(ratio)
      }
    })
    bar.addEventListener('mouseup', _event => {
      dragging = false
    })
  },

  reloadMedia (opts) {
    const player = this.player
    const { mediaId, mediaPath } = this.el.dataset

    player.attachSource(mediaPath)

    player.on(MediaPlayer.events.CAN_PLAY, () => this.canPlay(opts))

    this.mediaId = mediaId
  },

  loadAndPlayMedia (mediaId) {
    this.pushEvent('load-and-play-media', { 'media-id': mediaId })
  }
}
