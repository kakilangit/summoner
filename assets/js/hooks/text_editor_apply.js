/**
 * TextEditorApply — applies modal editor value back to form and updates preview.
 *
 * Expects `data-target` attribute pointing to the hidden textarea's ID.
 */
const TextEditorApply = {
  mounted() {
    this.el.addEventListener("click", () => {
      const target = document.getElementById(this.el.dataset.target)
      if (!target) return

      this._updatePreview(target)
      target.dispatchEvent(new Event("input", { bubbles: true }))
    })
  },
  _updatePreview(target) {
    const preview = document.getElementById(`text-editor-preview-${target.id}`)
    if (!preview) return

    const placeholder = preview.querySelector("[data-placeholder]")
    const content = preview.querySelector("[data-content]")

    if (target.value) {
      if (placeholder) placeholder.style.display = "none"
      if (content) { content.style.display = ""; content.textContent = target.value }
    } else {
      if (placeholder) placeholder.style.display = ""
      if (content) content.style.display = "none"
    }
  }
}

export default TextEditorApply
