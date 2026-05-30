/**
 * AutoResize — auto-grows a textarea to fit its content.
 */
const MIN_HEIGHT_PX = 96

const AutoResize = {
  mounted() {
    this.el.style.overflow = "hidden"
    this._resize()
    this.el.addEventListener("input", () => this._resize())
    this.el.addEventListener("keydown", (e) => {
      if (e.key !== "Enter") return

      e.stopPropagation()

      if (!e.shiftKey) {
        e.preventDefault()
        this.el.closest("form")?.requestSubmit()
      }
    })
    this.el.focus()
    const len = this.el.value.length
    this.el.setSelectionRange(len, len)
  },
  _resize() {
    this.el.style.height = "0"
    this.el.style.height = Math.max(this.el.scrollHeight, MIN_HEIGHT_PX) + "px"
  }
}

export default AutoResize
