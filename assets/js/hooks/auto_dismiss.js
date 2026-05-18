/**
 * AutoDismiss — fades out and removes the element after a delay.
 */
const DISMISS_DELAY_MS = 5_000
const FADE_DURATION_MS = 500

const AutoDismiss = {
  mounted() {
    this.timer = setTimeout(() => {
      this.el.style.transition = `opacity ${FADE_DURATION_MS}ms`
      this.el.style.opacity = "0"
      setTimeout(() => this.el.remove(), FADE_DURATION_MS)
    }, DISMISS_DELAY_MS)
  },
  destroyed() {
    clearTimeout(this.timer)
  }
}

export default AutoDismiss
