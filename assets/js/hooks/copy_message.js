/**
 * CopyMessage — copies message content to clipboard on button click.
 *
 * Expects a `[data-raw]` element for the text and `[data-copy]` button trigger.
 */
const FEEDBACK_DURATION_MS = 1_500

const CopyMessage = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-copy]")
      if (!btn) return
      e.preventDefault()
      e.stopPropagation()

      const prose = this.el.querySelector("[data-raw]")
      if (!prose) return

      const text = prose.getAttribute("data-raw") || ""
      navigator.clipboard.writeText(text).then(() => {
        const icon = btn.querySelector("span")
        if (!icon) return
        const orig = icon.className
        icon.className = "hero-check size-3 text-success"
        setTimeout(() => { icon.className = orig }, FEEDBACK_DURATION_MS)
      })
    })
  }
}

export default CopyMessage
