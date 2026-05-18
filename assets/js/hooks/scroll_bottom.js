/**
 * ScrollBottom — auto-scrolls to bottom and provides scroll navigation buttons.
 *
 * Creates floating top/bottom scroll buttons that appear when content overflows.
 */
const NEAR_BOTTOM_PX = 150
const BUTTON_THRESHOLD_PX = 50
const MIN_OVERFLOW_PX = 100

const ICON_UP = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4"><path fill-rule="evenodd" d="M10 17a.75.75 0 0 1-.75-.75V5.612L5.29 9.77a.75.75 0 0 1-1.08-1.04l5.25-5.5a.75.75 0 0 1 1.08 0l5.25 5.5a.75.75 0 1 1-1.08 1.04l-3.96-4.158V16.25A.75.75 0 0 1 10 17Z" clip-rule="evenodd" /></svg>'
const ICON_DOWN = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4"><path fill-rule="evenodd" d="M10 3a.75.75 0 0 1 .75.75v10.638l3.96-4.158a.75.75 0 1 1 1.08 1.04l-5.25 5.5a.75.75 0 0 1-1.08 0l-5.25-5.5a.75.75 0 1 1 1.08-1.04l3.96 4.158V3.75A.75.75 0 0 1 10 3Z" clip-rule="evenodd" /></svg>'
const BTN_CLASS = "btn btn-circle btn-sm btn-ghost bg-base-200/80 backdrop-blur shadow border border-base-300 hover:bg-base-300 pointer-events-auto"

const ScrollBottom = {
  mounted() {
    this._scrollToBottom()
    this._createButtons()
    this._onScroll = () => this._updateButtons()
    this.el.addEventListener("scroll", this._onScroll, { passive: true })
  },
  updated() {
    if (this._isNearBottom()) {
      this._scrollToBottom()
    }
    this._updateButtons()
  },
  destroyed() {
    this.el.removeEventListener("scroll", this._onScroll)
    if (this._wrapper) this._wrapper.remove()
  },
  _isNearBottom() {
    return this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < NEAR_BOTTOM_PX
  },
  _scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  },
  _scrollToTop() {
    this.el.scrollTop = 0
  },
  _createButtons() {
    const parent = this.el.parentElement
    if (parent && getComputedStyle(parent).position === "static") {
      parent.style.position = "relative"
    }

    const wrapper = document.createElement("div")
    wrapper.className = "absolute right-12 bottom-20 flex flex-col gap-1 z-10 pointer-events-none"

    this._topBtn = this._createButton(ICON_UP, "Scroll to top", () => this._scrollToTop())
    this._bottomBtn = this._createButton(ICON_DOWN, "Scroll to bottom", () => this._scrollToBottom())

    wrapper.appendChild(this._topBtn)
    wrapper.appendChild(this._bottomBtn)
    parent.appendChild(wrapper)
    this._wrapper = wrapper
    this._updateButtons()
  },
  _createButton(icon, title, onClick) {
    const btn = document.createElement("button")
    btn.className = BTN_CLASS
    btn.title = title
    btn.innerHTML = icon
    btn.addEventListener("click", onClick)
    return btn
  },
  _updateButtons() {
    const el = this.el
    const atTop = el.scrollTop < BUTTON_THRESHOLD_PX
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < BUTTON_THRESHOLD_PX
    const hasScroll = el.scrollHeight > el.clientHeight + MIN_OVERFLOW_PX

    this._topBtn.style.display = (hasScroll && !atTop) ? "" : "none"
    this._bottomBtn.style.display = (hasScroll && !atBottom) ? "" : "none"
  }
}

export default ScrollBottom
