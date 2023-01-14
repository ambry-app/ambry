export const SearchBox = {
  mounted () {
    const searchInput = document.getElementById('search-input')
    const clearSearch = document.getElementById('clear-search')

    window.addEventListener("ambry:search-box-shown", this.onShow)
    window.addEventListener("ambry:search-box-hidden", this.onHide)
    searchInput.addEventListener('input', this.onInput)
    clearSearch.addEventListener('click', this.onClear)
  },

  onShow (event) {},

  onHide (event) {
    const searchInput = document.getElementById('search-input')
    const clearSearch = document.getElementById('clear-search')

    window.setTimeout(() => {
      searchInput.value = ''
      clearSearch.classList.add('hidden')
    }, 100)
  },

  onInput (event) {
    const clearSearch = document.getElementById('clear-search')

    event.target.value == ''
      ? clearSearch.classList.add('hidden')
      : clearSearch.classList.remove('hidden')
  },

  onClear (event) {
    const searchInput = document.getElementById('search-input')
    const clearSearch = document.getElementById('clear-search')

    searchInput.value = ''
    searchInput.focus()
    clearSearch.classList.add('hidden')
  },

  destroyed () {
    const searchInput = document.getElementById('search-input')
    const clearSearch = document.getElementById('clear-search')

    window.removeEventListener("ambry:search-box-shown", this.onShow)
    window.removeEventListener("ambry:search-box-hidden", this.onHide)
    searchInput.removeEventListener('input', this.onInput)
    clearSearch.removeEventListener('click', this.onClear)
  }
}
