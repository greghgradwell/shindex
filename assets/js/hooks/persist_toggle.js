const ALLOWED_KEYS = ["show_cells"]

const PersistToggle = {
  mounted() {
    const key = this.el.dataset.storageKey

    if (!ALLOWED_KEYS.includes(key)) {
      console.error(`PersistToggle: Invalid storage key "${key}"`)
      return
    }

    const stored = localStorage.getItem(key)

    if (stored !== null) {
      const value = stored === "true"
      this.pushEvent("restore_toggle", { key: key, value: value })
    }

    this.handleEvent("persist_toggle", ({ key, value }) => {
      if (ALLOWED_KEYS.includes(key)) {
        localStorage.setItem(key, value.toString())
      }
    })
  }
}

export default PersistToggle
