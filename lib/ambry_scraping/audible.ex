defmodule AmbryScraping.Audible do
  @moduledoc """
  API client for Audible's public (undocumented but stable) catalog API.
  """

  use Boundary,
    deps: [AmbryScraping.HTMLToMD],
    exports: [Author, Product, Narrator, Series]

  alias AmbryScraping.Audible.Client
  alias AmbryScraping.Audible.Products

  defmodule Author do
    @moduledoc "Author name and ID only"
    defstruct [:id, :name]
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
  Searches for audiobooks.

  `query` is a plain string (searched as keywords) or a map of `:title` /
  `:author` / `:narrator` / `:keywords`. See
  `AmbryScraping.Audible.Products.search/2` for options (`:language`,
  `:marketplaces`).
  """
  def search_books(query, opts \\ []), do: Products.search(query, opts)

  @doc "The regional marketplace codes that can be searched."
  defdelegate marketplaces, to: Client

  @doc "Parses an operator's marketplace setting into a list of codes."
  defdelegate parse_marketplaces(setting), to: Client
end
