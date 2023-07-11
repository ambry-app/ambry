defmodule AmbryScraping.Audible.Browser do
  @moduledoc false

  alias AmbryScraping.Marionette.Browser

  @url "https://www.audible.com"

  def get_page_html(path, actions \\ []) do
    Browser.get_page_html("#{@url}#{path}", actions)
  end
end
