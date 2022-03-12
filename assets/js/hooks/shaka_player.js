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

    // server push event handlers
    this.handleEvent('reload-media', () => {
      this.reloadMedia()
    })

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

  loadMedia (mediaId) {
    this.pushEvent('load-media', { 'media-id': mediaId })
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
    this.pushEvent('playback-paused', { 'playback-time': time })
    this.time = time

    this.clearSyncInterval()
    this.clearUnloadHandler()
  },

  playbackRateChanged () {
    const playbackRate = this.audio.playbackRate

    if (playbackRate && playbackRate != this.playbackRate) {
      this.alpineSetPositionAndDuration(this.audio.currentTime, this.audio.duration, playbackRate)
      this.pushEvent('playback-rate-changed', { 'playback-rate': playbackRate })
      this.playbackRate = playbackRate
    }
  },

  playbackTimeUpdated () {
    const time = this.audio.currentTime

    if (time != this.time) {
      this.updateCurrentChapter(time)
      this.alpineSetPositionAndDuration(time, this.audio.duration, this.playbackRate)
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

  reloadMedia () {
    const audio = this.audio
    const { mediaId } = this.el.dataset

    if (mediaId === this.mediaId) {
      // no change was made
      return
    }

    if (!audio.paused) {
      audio.addEventListener(
        'pause',
        () => this.loadMediaFromDataset(this.el.dataset),
        { once: true }
      )
      this.pause()
    } else {
      this.loadMediaFromDataset(this.el.dataset)
    }
  },

  async loadMediaFromDataset (dataset) {
    const { mediaId, mediaPlaybackRate, mediaPosition, mediaChapters } = dataset
    const mediaPath = os.ios ? dataset.mediaHlsPath : dataset.mediaPath
    const player = this.player
    const audio = this.audio
    const time = parseFloat(mediaPosition)

    this.mediaId = mediaId
    this.playbackRate = mediaPlaybackRate
    this.time = time
    this.chapters = JSON.parse(mediaChapters).map((chapter, i) => {
      return {id: i, time: parseFloat(chapter.time), title: chapter.title}
    })

    this.updateCurrentChapter(time)

    try {
      await player.load(mediaPath, time)
      audio.playbackRate = parseFloat(mediaPlaybackRate)
      this.alpineSetPositionAndDuration(time, audio.duration, this.playbackRate)

      console.log('Shaka: Media loaded')
    } catch (e) {
      this.onError(e)
      return
    }
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
    Alpine.store('player').playbackRate = playbackRate
  },

  alpineSetCurrentChapter (chapter) {
    Alpine.store('player').currentChapter = chapter.id
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
  },

  updateCurrentChapter (time) {
    if (this.currentChapter && time >= this.currentChapter.start && time < this.currentChapter.end) {
      return
    }

    const chapters = this.chapters
    let currentChapter, nextChapter

    for (let i = chapters.length - 1; i >= 0; i--) {
      if (time >= chapters[i].time) {
        currentChapter = chapters[i]
        nextChapter = chapters[i+1]
        break;
      }
    }

    if (currentChapter) {
      this.currentChapter = {
        id: currentChapter.id,
        start: currentChapter.time,
        end: nextChapter?.time || this.audio.duration
      }

      this.alpineSetCurrentChapter(currentChapter)
    }
  }
}
