defmodule AmbryScraping.Audnexus do
  @moduledoc """
  Audnexus Authors and Chapters API.

  This is much faster than the Audible scraping API and returns the same data.
  """

  use Boundary, deps: [AmbryScraping.Image], exports: [Author, AuthorDetails, Chapters, Chapter]

  alias AmbryScraping.Audnexus.Authors
  alias AmbryScraping.Audnexus.Books

  defmodule Author do
    @moduledoc "Author name and ID only"
    defstruct [:id, :name]
  end

  defmodule AuthorDetails do
    @moduledoc "Author details including name, description, and image"
    defstruct [:id, :name, :description, :image]
  end

  defmodule Chapters do
    @moduledoc "Audiobook chapters"
    defstruct [:asin, :brand_intro_duration_ms, :brand_outro_duration_ms, :chapters]
  end

  defmodule Chapter do
    @moduledoc "Audiobook chapter details"
    defstruct [
      :length_ms,
      :start_offset_ms,
      :start_offset_sec,
      :title
    ]
  end

  @doc """
  Searches for authors by name.
  """
  def search_authors(query), do: Authors.search(query)

  @doc """
  Fetches the details of an author by their ID (ASIN).
  """
  def author_details(id), do: Authors.details(id)

  @doc """
  Fetches the chapters of an audiobook by its ID (ASIN).
  """
  def book_chapters(asin), do: Books.chapters(asin)
end
