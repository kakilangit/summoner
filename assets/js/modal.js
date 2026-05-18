/**
 * Modal scroll reset — fixes DaisyUI modal position bug.
 *
 * When a modal is reopened, the browser may retain the previous scroll offset
 * on the `.modal` element. This observer resets scrollTop whenever `modal-open`
 * is added.
 */
export function initModalScrollReset() {
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (mutation.attributeName !== "class") continue
      const el = mutation.target
      if (el.classList.contains("modal") && el.classList.contains("modal-open")) {
        requestAnimationFrame(() => { el.scrollTop = 0 })
      }
    }
  })

  observer.observe(document.body, {
    attributes: true,
    attributeFilter: ["class"],
    subtree: true
  })
}
