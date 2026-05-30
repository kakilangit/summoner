/**
 * MessageInput — chat composer behavior for submit, focus, and resizing.
 */
const MessageInput = {
  mounted() {
    this._resize()
    this.el.focus()

    this.el.addEventListener("input", () => this._resize())
    this.el.addEventListener("keydown", (e) => {
      if (e.key !== "Enter") return

      if (e.shiftKey) return

      e.preventDefault()
      this.el.closest("form")?.requestSubmit()
    })

    this.el.form.addEventListener("submit", () => {
      requestAnimationFrame(() => {
        this.el.value = ""
        this._resize()
        this.el.focus()
      })
    })
  },
  updated() {
    this._resize()
    this.el.focus()
  },
  _resize() {
    if (this.el.tagName !== "TEXTAREA") return

    this.el.style.overflow = "hidden"
    this.el.style.height = "0"
    this.el.style.height = Math.max(this.el.scrollHeight, 48) + "px"
  }
}

export default MessageInput
