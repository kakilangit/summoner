/**
 * MessageInput — auto-clears and refocuses after form submit.
 */
const MessageInput = {
  mounted() {
    this.el.focus()
    this.el.form.addEventListener("submit", () => {
      requestAnimationFrame(() => {
        this.el.value = ""
        this.el.focus()
      })
    })
  },
  updated() {
    this.el.focus()
  }
}

export default MessageInput
