defmodule AmbryScraping.GoodReads do
  @moduledoc """
  GoodReads web-scraping API
  """

  use Boundary,
    deps: [AmbryScraping.HTMLToMD, AmbryScraping.Marionette],
    exports: [
      AuthorDetails,
      Contributor,
      Edition,
      EditionDetails,
      Editions,
      PublishedDate,
      Series,
      Work
    ]

  alias AmbryScraping.GoodReads.Authors
  alias AmbryScraping.GoodReads.Books

  defmodule AuthorDetails do
    @moduledoc "Author details including name, description, and image"
    defstruct [:id, :name, :description, :image]
  end

  defmodule Contributor do
    @moduledoc "A contributor (e.g. author, narrator, illustrator, etc.)"
    defstruct [:id, :name, :type]
  end

  defmodule Edition do
    @moduledoc "Book edition"
    defstruct [
      :id,
      :title,
      :published,
      :publisher,
      :format,
      :contributors,
      :language,
      :thumbnail
      # Possible future improvements:
      # :isbn
      # :isbn10
      # :asin
    ]
  end

  defmodule EditionDetails do
    @moduledoc "Details for a specific edition of a book"
    defstruct [
      :id,
      :title,
      :authors,
      :series,
      :description,
      :cover_image,
      :format,
      :published,
      :publisher,
      :language
    ]
  end

  defmodule Editions do
    @moduledoc "Search results for book editions"
    defstruct [:id, :title, :primary_author, :first_published, :editions]
  end

  defmodule PublishedDate do
    @moduledoc "Published date of a book edition"
    defstruct [:date, :display_format]
  end

  defmodule Series do
    @moduledoc "Book series and sequence number in the series"
    defstruct [:id, :name, :number]
  end

  defmodule Work do
    @moduledoc "An individual work"
    defstruct [:id, :title, :contributors, :thumbnail]
  end

  @doc """
  Searches for authors by name.
  """
  def search_authors(query), do: Authors.search(query)

  @doc """
  Fetches the details of an author by their ID.
  """
  def author_details(id), do: Authors.details(id)

  @doc """
  Returns book search results for a given query
  """
  def search_books(query), do: Books.search(query)

  @doc """
  Returns list of editions for a given book
  """
  def editions(work_id), do: Books.editions(work_id)

  @doc """
  Returns the details for a given edition of a book
  """
  def edition_details(edition_id), do: Books.edition_details(edition_id)
end
