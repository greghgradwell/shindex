// LiveView DOM morphing completes within this delay after mounted() fires
const LIVEVIEW_MORPH_DELAY_MS = 50

const FocusFirstEmpty = {
  mounted() {
    this.focusFirstEmpty()
  },

  updated() {
    this.focusFirstEmpty()
  },

  focusFirstEmpty() {
    const inputs = this.el.querySelectorAll('input[type="text"]')

    for (const input of inputs) {
      if (!input.value || input.value.trim() === "") {
        const inputName = input.name
        setTimeout(() => {
          // Re-query for fresh DOM reference (original becomes stale after morph)
          const freshInput = this.el.querySelector(`input[name="${inputName}"]`)
          if (freshInput) {
            freshInput.focus()
          }
        }, LIVEVIEW_MORPH_DELAY_MS)
        return
      }
    }
  }
}

export default FocusFirstEmpty
