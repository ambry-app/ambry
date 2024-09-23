defmodule AmbrySchema.Sync do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Relay.Node, only: [to_global_id: 3]

  alias AmbrySchema.Resolvers

  interface :sync_result do
    field :id, non_null(:id)
    resolve_type &Resolvers.type/2
  end

  enum :deletion_type do
    value :book
    value :media
    value :person
    value :series
  end

  node object(:deletion) do
    field :type, non_null(:deletion_type)

    field :record_id, non_null(:id),
      resolve: fn deletion, _, _ ->
        dbg(deletion)
        {:ok, to_global_id(deletion.type, deletion.record_id, AmbrySchema)}
      end

    field :deleted_at, non_null(:datetime)

    interface :sync_result
  end

  object :sync_queries do
    field :sync, non_null(list_of(non_null(:sync_result))) do
      arg :since, :datetime

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.sync/2
    end
  end
end
