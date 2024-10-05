defmodule AmbrySchema.Media do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers, only: [dataloader: 1, dataloader: 2]

  alias AmbrySchema.Resolvers

  enum :media_processing_status do
    value :pending
    value :processing
    value :error
    value :ready
  end

  object :chapter do
    field :id, non_null(:id)
    field :title, :string
    field :start_time, non_null(:float)
    field :end_time, :float
  end

  node object(:media) do
    field :status, non_null(:media_processing_status)

    field :full_cast, non_null(:boolean)
    field :abridged, non_null(:boolean)
    field :duration, :float, resolve: Resolvers.resolve_decimal(:duration)
    field :mpd_path, :string
    field :hls_path, :string
    field :mp4_path, :string

    field :chapters, non_null(list_of(non_null(:chapter))), resolve: &Resolvers.chapters/3

    field :book, non_null(:book), resolve: dataloader(Resolvers)

    field :narrators, non_null(list_of(non_null(:narrator))),
      resolve: dataloader(Resolvers, args: %{order: {:asc, :name}})

    field :player_state, :player_state, resolve: &Resolvers.player_state_batch/3

    field :published, :date
    field :published_format, non_null(:date_format)

    field :description, :string
    field :thumbnails, :thumbnails

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)

    field :image_path, :string, deprecate: "use `thumbnails` instead"
  end

  node object(:media_narrator) do
    field :media, non_null(:media), resolve: dataloader(Resolvers, args: %{allow_all_media: true})
    field :narrator, non_null(:narrator), resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  enum :player_state_status do
    value :not_started
    value :in_progress
    value :finished
  end

  node object(:player_state) do
    field :playback_rate, non_null(:float), resolve: Resolvers.resolve_decimal(:playback_rate)
    field :position, non_null(:float), resolve: Resolvers.resolve_decimal(:position)
    field :status, non_null(:player_state_status)

    field :media, non_null(:media), resolve: dataloader(Resolvers, args: %{allow_all_media: true})

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  connection(node_type: :media)
  connection(node_type: :player_state)

  object :media_queries do
    connection field :player_states, node_type: :player_state do
      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.list_player_states/2
    end
  end

  object :media_mutations do
    payload field :load_player_state do
      description """
      Initializes a new player state or returns an existing player state for a given Media.
      """

      input do
        field :media_id, non_null(:id)
      end

      output do
        field :player_state, non_null(:player_state)
      end

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.load_player_state/2
    end

    payload field :update_player_state do
      input do
        field :media_id, non_null(:id)
        field :position, :float
        field :playback_rate, :float
      end

      output do
        field :player_state, non_null(:player_state)
      end

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.update_player_state/2
    end
  end
end
