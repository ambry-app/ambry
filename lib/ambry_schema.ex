defmodule AmbrySchema do
  @moduledoc false

  use Absinthe.Schema
  use Absinthe.Relay.Schema, :modern

  alias AmbrySchema.Resolvers

  import_types Absinthe.Type.Custom
  import_types AmbrySchema.Nodes
  import_types AmbrySchema.Accounts
  import_types AmbrySchema.People
  import_types AmbrySchema.Books
  import_types AmbrySchema.Media
  import_types AmbrySchema.Sessions

  query do
    import_fields :node_query
    import_fields :account_queries
    import_fields :book_queries
    import_fields :media_queries
  end

  mutation do
    import_fields :session_mutations
    import_fields :media_mutations
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
