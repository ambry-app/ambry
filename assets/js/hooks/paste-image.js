// Lets an image upload area accept images pasted from the clipboard
// (screenshots, copied web images). Attached to a drop-target div with
// `data-upload-name` naming the LiveView upload config; pasted image files
// are piped into the same upload pipeline as drag-and-drop or the file
// picker.
export const PasteImageHook = {
  mounted() {
    this.handler = (event) => {
      const files = Array.from(event.clipboardData?.files || []).filter((file) =>
        file.type.startsWith("image/"),
      )

      if (files.length > 0) {
        event.preventDefault()
        this.uploadTo(this.el, this.el.dataset.uploadName, files.slice(0, 1))
      }
    }

    window.addEventListener("paste", this.handler)
  },

  destroyed() {
    window.removeEventListener("paste", this.handler)
  },
}
