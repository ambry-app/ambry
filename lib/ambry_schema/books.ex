defmodule AmbrySchema.Books do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers, only: [dataloader: 1, dataloader: 2]

  alias AmbrySchema.Resolvers

  enum :date_format do
    value :full
    value :year_month
    value :year
  end

  node object(:series_book) do
    field :book_number, non_null(:decimal)

    field :book, non_null(:book), resolve: dataloader(Resolvers)
    field :series, non_null(:series), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:series) do
    field :name, non_null(:string)

    connection field :series_books, node_type: :series_book do
      resolve &Resolvers.list_series_books/3
    end

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)

    interface :search_result
  end

  node object(:book) do
    field :title, non_null(:string)
    field :published, non_null(:date)
    field :published_format, non_null(:date_format)

    field :authors, non_null(list_of(non_null(:author))),
      resolve: dataloader(Resolvers, args: %{order: {:asc, :name}})

    field :series_books, non_null(list_of(non_null(:series_book))), resolve: dataloader(Resolvers)

    field :media, non_null(list_of(non_null(:media))),
      resolve: dataloader(Resolvers, args: %{order: {:desc, :inserted_at}})

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)

    interface :search_result

    field :image_path, :string, deprecate: "imagePath has been moved to `Media`"
    field :description, :string, deprecate: "description has been moved to `Media`"
  end

  node object(:book_author) do
    field :author, non_null(:author), resolve: dataloader(Resolvers)
    field :book, non_null(:book), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  connection(node_type: :book)
  connection(node_type: :series_book)

  object :book_queries do
    connection field :books, node_type: :book do
      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.list_books/2
    end
  end
end
