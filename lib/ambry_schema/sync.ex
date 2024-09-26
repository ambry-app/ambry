defmodule AmbrySchema.Sync do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Relay.Node, only: [to_global_id: 3]

  alias AmbrySchema.Resolvers

  enum :deletion_type do
    value :person
    value :author
    value :narrator
    value :book
    value :book_author
    value :series
    value :series_book
    value :media
    value :media_narrator
  end

  node object(:deletion) do
    field :type, non_null(:deletion_type)

    field :record_id, non_null(:id),
      resolve: fn deletion, _, _ ->
        {:ok, to_global_id(deletion.type, deletion.record_id, AmbrySchema)}
      end

    field :deleted_at, non_null(:datetime)
  end

  object :sync_queries do
    field :people_changed_since, non_null(list_of(non_null(:person))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.people_changed_since/2
    end

    field :authors_changed_since, non_null(list_of(non_null(:author))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.authors_changed_since/2
    end

    field :narrators_changed_since, non_null(list_of(non_null(:narrator))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.narrators_changed_since/2
    end

    field :books_changed_since, non_null(list_of(non_null(:book))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.books_changed_since/2
    end

    field :book_authors_changed_since, non_null(list_of(non_null(:book_author))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.book_authors_changed_since/2
    end

    field :series_changed_since, non_null(list_of(non_null(:series))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.series_changed_since/2
    end

    field :series_books_changed_since, non_null(list_of(non_null(:series_book))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.series_books_changed_since/2
    end

    field :media_changed_since, non_null(list_of(non_null(:media))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.media_changed_since/2
    end

    field :media_narrators_changed_since, non_null(list_of(non_null(:media_narrator))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.media_narrators_changed_since/2
    end

    field :deletions_since, non_null(list_of(non_null(:deletion))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.deletions_since/2
    end
  end
end
