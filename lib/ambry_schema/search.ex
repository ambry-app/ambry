defmodule AmbrySchema.Search do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  alias AmbrySchema.Resolvers

  connection(node_type: :node)

  object :search_queries do
    connection field :search, node_type: :node do
      arg :query, non_null(:string)

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.search/2
    end
  end
end
