export default {
  mediaId: undefined,
  duration: {real: undefined, actual: undefined},
  progress: {real: undefined, actual: undefined, percent: undefined},
  playbackRate: undefined,
  chapters: [],
  playing: false,
  currentChapter: undefined,

  loadMedia(id, actualTime, actualDuration, playbackRate, chapters) {
    this.mediaId = id
    this.playbackRate = playbackRate
    this.chapters = chapters

    this.setDuration(actualDuration)
    this.setProgress(actualTime)
  },

  setPlaying() {
    this.playing = true
  },

  setPaused() {
    this.playing = false
  },

  setDuration(actualDuration) {
    const realDuration = actualDuration / this.playbackRate

    this.duration = {real: realDuration, actual: actualDuration}
  },

  setProgress(actualTime) {
    const realTime = actualTime / this.playbackRate
    const percentage = ((realTime / this.duration.real) * 100).toFixed(2)

    this.progress = {real: realTime, actual: actualTime, percent: percentage}

    this.updateChapter()
  },

  setPlaybackRate(playbackRate) {
    this.playbackRate = playbackRate

    this.setDuration(this.duration.actual)
    this.setProgress(this.progress.actual)
  },

  updateChapter() {
    const actualTime = this.progress.actual
    const chapters = this.chapters
    let currentChapter = this.currentChapter
    let nextChapter

    if (currentChapter && actualTime >= currentChapter.start && actualTime < currentChapter.end) {
      return
    }

    for (let i = chapters.length - 1; i >= 0; i--) {
      if (actualTime >= chapters[i].time) {
        currentChapter = chapters[i]
        nextChapter = chapters[i+1]
        break;
      }
    }

    if (currentChapter) {
      this.currentChapter = {
        id: currentChapter.id,
        start: currentChapter.time,
        end: nextChapter?.time || (this.duration.actual)
      }
    }
  }
}
