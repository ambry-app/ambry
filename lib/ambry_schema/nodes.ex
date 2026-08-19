defmodule AmbrySchema.Nodes do
  @moduledoc """
  The Relay node interface, for the global ids the sync queries hand out.

  There is no `node(id:)` root field any more. It existed for a
  server-driven mobile client that was retired; the app that replaced it is
  offline-first and reads its own SQLite, asking this API only what changed
  since a cursor. Everything reachable *only* through `node` went with it.
  """

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  alias AmbrySchema.Resolvers

  node interface do
    resolve_type &Resolvers.type/2
  end
end
