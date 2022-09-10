defmodule AmbrySchema.Search do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  alias AmbrySchema.Resolvers

  interface :search_result do
    field :id, non_null(:id)
    resolve_type &Resolvers.type/2
  end

  connection(node_type: :search_result)

  object :search_queries do
    connection field :search, node_type: :search_result do
      arg :query, non_null(:string)

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.search/2
    end
  end
end
