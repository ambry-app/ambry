defmodule AmbrySchema.Books do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias AmbrySchema.Resolvers

  enum :date_format do
    value :full
    value :year_month
    value :year
  end

  node object(:series_book) do
    field :book_number, non_null(:decimal)

    # Which series comes first when a book is in several. Additive: clients
    # that don't ask for it are unaffected, and one that does can order a
    # book's series the way the operator did.
    field :position, non_null(:integer)

    field :book, non_null(:book), resolve: dataloader(Resolvers)
    field :series, non_null(:series), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:series) do
    field :name, non_null(:string)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:universe) do
    field :name, non_null(:string)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:book_universe) do
    field :book, non_null(:book), resolve: dataloader(Resolvers)
    field :universe, non_null(:universe), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:book) do
    field :title, non_null(:string)
    field :published, non_null(:date)
    field :published_format, non_null(:date_format)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:book_author) do
    # Billing order: position 0 is the book's primary author.
    field :position, non_null(:integer)

    field :author, non_null(:author), resolve: dataloader(Resolvers)
    field :book, non_null(:book), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end
end
