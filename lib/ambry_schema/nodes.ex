defmodule AmbrySchema.Nodes do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  alias AmbrySchema.Resolvers

  node interface do
    resolve_type &Resolvers.type/2
  end

  object :node_query do
    node field do
      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.node/2
    end
  end
end
