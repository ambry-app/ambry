defmodule AmbryScraping.Audible do
  @moduledoc """
  A mix of web scraping and API scraping for Audible.
  """

  use Boundary,
    deps: [AmbryScraping.HTMLToMD, AmbryScraping.Image, AmbryScraping.Marionette],
    exports: [AuthorDetails, Author, Product, Narrator, Series]

  alias AmbryScraping.Audible.Authors
  alias AmbryScraping.Audible.Products

  defmodule Author do
    @moduledoc "Author name and ID only"
    defstruct [:id, :name]
  end

  defmodule AuthorDetails do
    @moduledoc "Author details including name, description, and image"
    defstruct [:id, :name, :description, :image]
  end

  defmodule Narrator do
    @moduledoc "Narrator name"
    defstruct [:name]
  end

  defmodule Series do
    @moduledoc "Series title and the sequence number of the book in the series"
    defstruct [:id, :sequence, :title]
  end

  defmodule Product do
    @moduledoc "Audiobook details"
    defstruct [
      :id,
      :title,
      :authors,
      :narrators,
      :series,
      :description,
      :cover_image,
      :format,
      :published,
      :publisher,
      :language
    ]
  end

  @doc """
  Searches for authors by name.

  This function uses web scraping to search for authors on the Audible website.
  """
  def search_authors(query), do: Authors.search(query)

  @doc """
  Fetches the details of an author by their ID (ASIN).

  This functions uses web scraping to fetch the details of an author from the
  Audible website.
  """
  def author_details(id), do: Authors.details(id)

  @doc """
  Searches for audiobooks by name.

  This function uses the public Audible API to search for audiobooks.
  """
  def search_books(query), do: Products.search(query)
end
