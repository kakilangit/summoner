/**
 * TextEditorModal — syncs a modal textarea with a hidden form field.
 *
 * Expects `data-target` attribute pointing to the hidden textarea's ID.
 * Syncs value into the modal when opened, and back on every keystroke.
 */
const TextEditorModal = {
  mounted() {
    const targetId = this.el.dataset.target
    const target = document.getElementById(targetId)
    const modal = this.el.closest(".modal")

    this._observer = new MutationObserver(() => {
      if (modal.classList.contains("modal-open")) {
        this.el.value = target.value
        this.el.focus()
      }
    })
    this._observer.observe(modal, { attributes: true, attributeFilter: ["class"] })

    this.el.addEventListener("input", () => {
      target.value = this.el.value
    })
  },
  destroyed() {
    if (this._observer) this._observer.disconnect()
  }
}

export default TextEditorModal
