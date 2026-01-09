const GhostAutocomplete = {
  mounted() {
    this.input = this.el.querySelector("[data-ghost-input]")
    this.ghost = this.el.querySelector("[data-ghost-text]")
    this.spacer = this.el.querySelector("[data-ghost-spacer]")
    this.suggestions = this.parseSuggestions(this.el.dataset.suggestions)
    this.dismissed = false

    this.input.addEventListener("input", () => this.handleInput())
    this.input.addEventListener("keydown", (e) => this.handleKeydown(e))
    this.input.addEventListener("focus", () => this.updateGhost())
    this.input.addEventListener("blur", () => this.clearGhost())

    this.updateGhost()

    // Auto-focus if autofocus attribute is present
    if (this.input.hasAttribute("autofocus")) {
      this.input.focus()
    }
  },

  updated() {
    const newSuggestions = this.parseSuggestions(this.el.dataset.suggestions)
    if (JSON.stringify(newSuggestions) !== JSON.stringify(this.suggestions)) {
      this.suggestions = newSuggestions
      this.updateGhost()
    }
  },

  parseSuggestions(json) {
    try {
      return JSON.parse(json || "[]")
    } catch {
      return []
    }
  },

  handleInput() {
    const value = this.input.value.toUpperCase()
    this.input.value = value
    this.dismissed = false
    this.updateGhost()
  },

  handleKeydown(e) {
    if (e.key === "Tab" || e.key === "ArrowRight") {
      if (this.ghost.textContent && !this.dismissed) {
        e.preventDefault()
        this.input.value += this.ghost.textContent
        this.ghost.textContent = ""
        this.pushValue()
      }
    } else if (e.key === "Delete" || e.key === "Escape") {
      if (this.ghost.textContent) {
        e.preventDefault()
        this.dismissed = true
        this.ghost.textContent = ""
      }
    } else if (e.key === "Enter") {
      // Let form submit with current user input (ignore ghost)
      this.ghost.textContent = ""
    }
  },

  updateGhost() {
    const value = this.input.value.toUpperCase()

    // Always update spacer to match input for positioning
    this.spacer.textContent = value

    if (this.dismissed || !value) {
      this.ghost.textContent = ""
      return
    }

    const match = this.suggestions
      .filter((s) => s.toUpperCase().startsWith(value) && s.toUpperCase() !== value)
      .sort()[0]

    if (match) {
      this.ghost.textContent = match.toUpperCase().slice(value.length)
    } else {
      this.ghost.textContent = ""
    }
  },

  clearGhost() {
    this.ghost.textContent = ""
  },

  pushValue() {
    this.pushEventTo(this.el, "ghost_value_changed", { value: this.input.value })
  },
}

export default GhostAutocomplete
