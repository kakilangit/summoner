/**
 * FocusOnUpdate — focuses the element on mount and every update.
 */
const FocusOnUpdate = {
  mounted() {
    this.el.focus()
  },
  updated() {
    this.el.focus()
  }
}

export default FocusOnUpdate
