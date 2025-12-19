defmodule AmbrySchema do
  @moduledoc false

  use Boundary,
    type: :strict,
    deps: [
      # External
      Absinthe,
      Absinthe.Plug,
      Absinthe.Relay,
      Dataloader,
      Decimal,
      Ecto,
      Plug,
      # Internal
      Ambry
    ],
    exports: [ContextPlug]

  use Absinthe.Schema
  use Absinthe.Relay.Schema, :modern

  alias AmbrySchema.Resolvers

  import_types Absinthe.Type.Custom
  import_types AmbrySchema.Nodes
  import_types AmbrySchema.Accounts
  import_types AmbrySchema.People
  import_types AmbrySchema.Books
  import_types AmbrySchema.Media
  import_types AmbrySchema.Playback
  import_types AmbrySchema.Sessions
  import_types AmbrySchema.Search
  import_types AmbrySchema.Sync

  query do
    import_fields :node_query
    import_fields :account_queries
    import_fields :book_queries
    import_fields :media_queries
    import_fields :search_queries
    import_fields :sync_queries
  end

  mutation do
    import_fields :session_mutations
    import_fields :media_mutations
    import_fields :playback_mutations
  end

  @impl Absinthe.Schema
  def context(ctx) do
    loader = Dataloader.add_source(Dataloader.new(), Resolvers, Resolvers.data())

    Map.put(ctx, :loader, loader)
  end

  @impl Absinthe.Schema
  def plugins do
    [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
  end
end
