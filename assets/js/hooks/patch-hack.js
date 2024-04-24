export const PatchHackHook = {
  mounted() {
    history.replaceState({ id: this.liveSocket.main.id, type: "patch" }, "")
  },
}
