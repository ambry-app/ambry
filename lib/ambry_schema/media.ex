defmodule AmbrySchema.Media do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers, only: [dataloader: 1, dataloader: 2]

  alias AmbrySchema.Resolvers

  object :chapter do
    field :id, non_null(:id)
    field :title, :string
    field :start_time, non_null(:decimal)
    field :end_time, :decimal
  end

  node object(:media) do
    field :full_cast, non_null(:boolean)
    field :abridged, non_null(:boolean)
    field :duration, :decimal
    field :mpd_path, :string
    field :hls_path, :string

    field :chapters, non_null(list_of(non_null(:chapter))), resolve: &Resolvers.chapters/3

    field :book, non_null(:book), resolve: dataloader(Resolvers)

    field :narrators, non_null(list_of(non_null(:narrator))),
      resolve: dataloader(Resolvers, args: %{order: {:asc, :name}})

    field :player_state, :player_state, resolve: &Resolvers.player_state_batch/3

    field :inserted_at, non_null(:naive_datetime)
    field :updated_at, non_null(:naive_datetime)
  end

  enum :player_state_status do
    value :not_started
    value :in_progress
    value :finished
  end

  node object(:player_state) do
    field :playback_rate, non_null(:decimal)
    field :position, non_null(:decimal)
    field :status, non_null(:player_state_status)

    field :media, non_null(:media), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:naive_datetime)
    field :updated_at, non_null(:naive_datetime)
  end

  connection(node_type: :media)
  connection(node_type: :player_state)

  object :media_queries do
    connection field :player_states, node_type: :player_state do
      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.list_player_states/2
    end
  end
end
