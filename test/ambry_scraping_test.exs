defmodule AmbryScrapingTest do
  use ExUnit.Case

  describe "web_scraping_available?" do
    test "returns false because the web scraping service is not available in test mode" do
      refute AmbryScraping.web_scraping_available?()
    end
  end
end
