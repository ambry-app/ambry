defmodule AmbryScraping.GoodReads.Browser do
  @moduledoc false

  alias AmbryScraping.Marionette.Browser

  @url "https://www.goodreads.com"
  @prepend_actions [
    # wait for page to finish loading
    wait_for_no: "svg[aria-label='Loading interface...']",
    # close login pop-up if it appears
    maybe_click: "button[aria-label='Close']"
  ]

  def get_page_html(path, actions \\ []) do
    Browser.get_page_html("#{@url}#{path}", @prepend_actions ++ actions)
  end
end
