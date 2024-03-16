// Polyfill initialization:

import shaka, { Player } from "shaka-player"
import Decimal from "decimal.js"
import os from "platform-detect/os.mjs"

function initPolyfills() {
  shaka.polyfill.installAll()

  if (Player.isBrowserSupported()) {
    console.log("Shaka: Polyfills installed")
  } else {
    // This browser does not have the minimum set of APIs we need.
    console.error("Shaka: Browser not supported!")
  }
}

document.addEventListener("DOMContentLoaded", initPolyfills)

// Shaka player hook:

// TODO: we should clean up all event listeners if the hook ever unmounts.
// This (I think) isn't currently possible, but a feature to "unload the current
// media" might eventually be implemented, in which case it will be necessary.
export const ShakaPlayerHook = {
  async mounted() {
    console.log("Shaka: Mounting...")

    const [audio] = this.el.getElementsByTagName("audio")
    const player = new Player()
    await player.attach(audio)

    const dataset = this.el.dataset

    // shaka event handlers
    player.addEventListener("error", (event) => this.onError(event))

    // audio element event handlers
    audio.addEventListener("play", () => this.playbackStarted())
    audio.addEventListener("pause", () => this.playbackPaused())
    audio.addEventListener("ended", () => this.playbackPaused())
    audio.addEventListener("ratechange", () => this.playbackRateChanged())
    audio.addEventListener("seeked", () => this.seeked())

    // LiveView event handlers
    this.el.addEventListener("ambry:toggle-playback", () => this.playPause())
    this.el.addEventListener("ambry:seek", (event) => this.seek(new Decimal(event.detail.value)))
    this.el.addEventListener("ambry:seek-relative", (event) => this.seekRelative(new Decimal(event.detail.value)))
    this.el.addEventListener("ambry:set-playback-rate", (event) =>
      this.setPlaybackRate(new Decimal(event.detail.value))
    )
    this.el.addEventListener("ambry:increment-playback-rate", () => this.incrementPlaybackRate())
    this.el.addEventListener("ambry:decrement-playback-rate", () => this.decrementPlaybackRate())
    this.el.addEventListener("ambry:load-and-play-media", (event) => this.loadAndPlayMedia(event.detail.id))

    this.audio = audio
    this.player = player
    window.mediaPlayer = this

    this.loadMediaFromDataset(dataset)
  },

  // player controls

  playPause() {
    if (this.isPaused()) {
      this.play()
    } else {
      this.pause()
    }
  },

  seek(time) {
    this.setCurrentTime(time)
  },

  seekRelative(seconds) {
    const currentTime = this.getCurrentTime()
    const duration = this.getDuration()
    const delta = seconds.mul(this.playbackRate)

    let newTime = currentTime.add(delta)

    newTime = newTime.lt(0) ? new Decimal(0) : newTime
    newTime = newTime.gt(duration) ? duration : newTime

    this.setCurrentTime(newTime)

    // pre-emptive server update for better UI experience
    this.pushEvent("playback-time-updated", { "playback-time": newTime })
  },

  seekRatio(ratio) {
    const duration = this.getDuration()
    const newTime = duration.mul(ratio)

    this.setCurrentTime(newTime)
  },

  incrementPlaybackRate() {
    const rate = this.getPlaybackRate()
    const newRate = rate.add("0.05")

    this.setPlaybackRate(newRate.gt(3) ? new Decimal(3) : newRate)
  },

  decrementPlaybackRate() {
    const rate = this.getPlaybackRate()
    const newRate = rate.sub("0.05")

    this.setPlaybackRate(newRate.lt("0.5") ? new Decimal("0.5") : newRate)
  },

  loadAndPlayMedia(mediaId) {
    this.pushEvent("load-media", { "media-id": mediaId }, () => {
      this.reloadMedia(true)
    })
  },

  // event handlers

  onError(eventOrException) {
    console.error("Shaka: Error:", eventOrException)
  },

  playbackStarted() {
    this.setPersistInterval()
    this.setUpdateInterval()
    this.setUnloadHandler()

    this.pushEvent("playback-started")
  },

  playbackPaused() {
    this.clearPersistInterval()
    this.clearUpdateInterval()
    this.clearUnloadHandler()

    this.pushEvent("playback-paused", { "playback-time": this.getCurrentTime() })
  },

  playbackRateChanged() {
    const playbackRate = this.getPlaybackRate()

    if (!playbackRate.eq(0) && !this.playbackRate.eq(playbackRate)) {
      this.pushEvent("playback-rate-changed", { "playback-rate": playbackRate })
      this.playbackRate = playbackRate
    }
  },

  seeked() {
    this.pushEvent("playback-time-updated", { "playback-time": this.getCurrentTime(), persist: true })
  },

  beforeUnload(e) {
    e.preventDefault()
    return ""
  },

  reloadMedia(autoplay = false) {
    const { mediaId } = this.el.dataset

    if (mediaId === this.mediaId) {
      // no change was made
      return
    }

    if (!this.isPaused()) {
      this.audio.addEventListener("pause", () => this.loadMediaFromDataset(this.el.dataset, autoplay), { once: true })
      this.pause()
    } else {
      this.loadMediaFromDataset(this.el.dataset, autoplay)
    }
  },

  async loadMediaFromDataset(dataset, autoplay = false) {
    if (dataset.mediaUnloaded === "") {
      console.log("Shaka: No media to load")
      this.loaded = false
      return
    }

    const { mediaId, mediaPlaybackRate, mediaPosition } = dataset
    const player = this.player
    const initTime = new Decimal(mediaPosition)

    this.mediaId = mediaId
    this.playbackRate = new Decimal(mediaPlaybackRate)
    this.loaded = true

    try {
      if (os.ios) {
        await player.load(dataset.mediaHlsPath)
      } else {
        await player.load(dataset.mediaPath, initTime.toNumber())
      }
      this.setPlaybackRate(this.playbackRate)

      console.log("Shaka: Media loaded")

      if (autoplay) {
        this.play()
      }
    } catch (e) {
      this.onError(e)
      return
    }
  },

  // Audio element interface

  play() {
    this.audio.play()
  },

  pause() {
    this.audio.pause()
  },

  setCurrentTime(time) {
    this.audio.currentTime = time.toNumber()
  },

  getCurrentTime() {
    return new Decimal(this.audio.currentTime)
  },

  setPlaybackRate(rate) {
    this.audio.playbackRate = rate.toNumber()
  },

  getPlaybackRate() {
    return new Decimal(this.audio.playbackRate)
  },

  getDuration() {
    return new Decimal(this.audio.duration)
  },

  isPaused() {
    return this.audio.paused
  },

  // Helpers

  setPersistInterval() {
    this.persistInterval = window.setInterval(() => {
      this.pushEvent("playback-time-updated", { "playback-time": this.getCurrentTime(), persist: true })
    }, 60000)
  },

  clearPersistInterval() {
    window.clearInterval(this.persistInterval)
  },

  setUpdateInterval() {
    this.updateInterval = window.setInterval(() => {
      this.pushEvent("playback-time-updated", { "playback-time": this.getCurrentTime() })
    }, 1000)
  },

  clearUpdateInterval() {
    window.clearInterval(this.updateInterval)
  },

  setUnloadHandler() {
    window.addEventListener("beforeunload", this.beforeUnload)
  },

  clearUnloadHandler() {
    window.removeEventListener("beforeunload", this.beforeUnload)
  },
}
