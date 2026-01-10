const BatchEditKeyboard = {
  mounted() {
    this.handleKeydown = (e) => {
      if (e.ctrlKey && e.key === "Enter") {
        e.preventDefault()

        // Collect form data
        const form = this.el.querySelector("form")
        if (form) {
          const formData = new FormData(form)
          const params = Object.fromEntries(formData.entries())
          this.pushEvent("save_and_next", params)
        }
      }
    }
    document.addEventListener("keydown", this.handleKeydown)
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeydown)
  }
}

export default BatchEditKeyboard
