const AutoConfirmUpload = {
  mounted() {
    // When upload completes, automatically trigger confirm to show Save/Cancel
    // data-target contains the LiveComponent CID (extracted via @myself.cid)
    const cid = this.el.dataset.target

    if (!cid) {
      console.error("AutoConfirmUpload: missing data-target attribute on", this.el.id)
      return
    }

    try {
      this.pushEventTo(cid, "confirm_upload", {})
    } catch (error) {
      console.error("AutoConfirmUpload: failed to push event:", error)
    }
  }
}

export default AutoConfirmUpload
