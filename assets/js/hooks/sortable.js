/**
 * Sortable — drag-and-drop reordering via native HTML5 drag API.
 *
 * Expects child elements with `data-sortable-id` attributes.
 * Pushes the event named in `data-sortable-event` (default "reorder_members")
 * with sorted IDs on drop.
 */
const Sortable = {
  mounted() {
    this._dragging = null
    this._eventName = this.el.dataset.sortableEvent || "reorder_members"

    this.el.addEventListener("dragstart", (e) => {
      const item = e.target.closest("[data-sortable-id]")
      if (!item) return
      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData("text/plain", item.dataset.sortableId)
      item.classList.add("opacity-50")
      this._dragging = item
    })

    this.el.addEventListener("dragend", () => {
      if (this._dragging) {
        this._dragging.classList.remove("opacity-50")
        this._dragging = null
      }
    })

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
      e.dataTransfer.dropEffect = "move"
      const target = e.target.closest("[data-sortable-id]")
      if (!target || target === this._dragging) return

      const rect = target.getBoundingClientRect()
      const midY = rect.top + rect.height / 2
      if (e.clientY < midY) {
        target.parentNode.insertBefore(this._dragging, target)
      } else {
        target.parentNode.insertBefore(this._dragging, target.nextSibling)
      }
    })

    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      const items = this.el.querySelectorAll("[data-sortable-id]")
      const ids = Array.from(items).map((el) => el.dataset.sortableId)
      this.pushEvent(this._eventName, { ids })
    })
  }
}

export default Sortable
