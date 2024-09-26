defmodule AmbrySchema.People do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers, only: [dataloader: 1, dataloader: 2]

  alias AmbrySchema.Resolvers

  node object(:person) do
    field :name, non_null(:string)
    field :description, :string
    field :image_path, :string

    field :authors, non_null(list_of(non_null(:author))),
      resolve: dataloader(Resolvers, args: %{order: {:asc, :name}})

    field :narrators, non_null(list_of(non_null(:narrator))),
      resolve: dataloader(Resolvers, args: %{order: {:asc, :name}})

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)

    interface :search_result
  end

  node object(:author) do
    field :name, non_null(:string)

    field :person, non_null(:person), resolve: dataloader(Resolvers)

    connection field :authored_books, node_type: :book do
      resolve &Resolvers.list_authored_books/3
    end

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:narrator) do
    field :name, non_null(:string)

    field :person, non_null(:person), resolve: dataloader(Resolvers)

    connection field :narrated_media, node_type: :media do
      resolve &Resolvers.list_narrated_media/3
    end

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end
end
