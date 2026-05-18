/**
 * DownloadFile — triggers a browser download from a server-pushed event.
 *
 * Listens for "download_file" event with {filename, content, content_type}.
 */
const DownloadFile = {
  mounted() {
    this.handleEvent("download_file", ({ filename, content, content_type }) => {
      const blob = new Blob([content], { type: content_type || "text/markdown" })
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = filename
      document.body.appendChild(a)
      a.click()
      setTimeout(() => { URL.revokeObjectURL(url); a.remove() }, 100)
    })
  }
}

export default DownloadFile
