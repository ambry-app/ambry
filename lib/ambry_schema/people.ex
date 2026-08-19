defmodule AmbrySchema.People do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias AmbrySchema.Resolvers

  object :thumbnails do
    field :extra_small, non_null(:string)
    field :small, non_null(:string)
    field :medium, non_null(:string)
    field :large, non_null(:string)
    field :extra_large, non_null(:string)

    field :thumbhash, non_null(:string)
    field :blurhash, :string
  end

  node object(:person) do
    field :name, non_null(:string)
    field :description, :string
    field :thumbnails, :thumbnails

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)

    field :image_path, :string, deprecate: "use `thumbnails` instead"
  end

  node object(:author) do
    field :name, non_null(:string)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:author_person) do
    field :author, non_null(:author), resolve: dataloader(Resolvers)
    field :person, non_null(:person), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  node object(:narrator) do
    field :name, non_null(:string)

    field :person, non_null(:person), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end
end
