defmodule AmbrySchema.Playback do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers, only: [dataloader: 2]

  alias AmbrySchema.Resolvers

  # ============================================================================
  # Enums
  # ============================================================================

  enum :playthrough_status do
    value :in_progress
    value :finished
    value :abandoned
  end

  enum :playback_event_type do
    value :start
    value :play
    value :pause
    value :seek
    value :rate_change
    value :finish
    value :abandon
    value :resume
  end

  enum :device_type do
    value :ios
    value :android
    value :web
  end

  # ============================================================================
  # Output Types
  # ============================================================================

  object :device do
    field :id, non_null(:id)
    field :type, non_null(:device_type)
    field :brand, :string
    field :model_name, :string
    field :browser, :string
    field :browser_version, :string
    field :os_name, :string
    field :os_version, :string
    field :last_seen_at, non_null(:datetime)
  end

  object :playthrough do
    field :id, non_null(:id)
    field :status, non_null(:playthrough_status)
    field :started_at, non_null(:datetime)
    field :finished_at, :datetime
    field :abandoned_at, :datetime
    field :deleted_at, :datetime
    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)

    field :media, non_null(:media), resolve: dataloader(Resolvers, args: %{allow_all_media: true})
  end

  object :playback_event do
    field :id, non_null(:id)
    field :playthrough_id, non_null(:id)
    field :device_id, :id
    field :type, non_null(:playback_event_type)
    field :timestamp, non_null(:datetime)
    field :position, :float, resolve: Resolvers.resolve_decimal(:position)
    field :playback_rate, :float, resolve: Resolvers.resolve_decimal(:playback_rate)
    field :from_position, :float, resolve: Resolvers.resolve_decimal(:from_position)
    field :to_position, :float, resolve: Resolvers.resolve_decimal(:to_position)
    field :previous_rate, :float, resolve: Resolvers.resolve_decimal(:previous_rate)
  end

  # ============================================================================
  # Input Types
  # ============================================================================

  input_object :device_input do
    field :id, non_null(:id)
    field :type, non_null(:device_type)
    field :brand, :string
    field :model_name, :string
    field :browser, :string
    field :browser_version, :string
    field :os_name, :string
    field :os_version, :string
  end

  input_object :playthrough_input do
    field :id, non_null(:id)
    field :media_id, non_null(:id)
    field :status, non_null(:playthrough_status)
    field :started_at, non_null(:datetime)
    field :finished_at, :datetime
    field :abandoned_at, :datetime
    field :deleted_at, :datetime
  end

  input_object :playback_event_input do
    field :id, non_null(:id)
    field :playthrough_id, non_null(:id)
    field :type, non_null(:playback_event_type)
    field :timestamp, non_null(:datetime)
    field :position, :float
    field :playback_rate, :float
    field :from_position, :float
    field :to_position, :float
    field :previous_rate, :float
  end

  input_object :sync_progress_input do
    field :last_sync_time, :datetime
    field :device, non_null(:device_input)
    field :playthroughs, non_null(list_of(non_null(:playthrough_input)))
    field :events, non_null(list_of(non_null(:playback_event_input)))
  end

  # ============================================================================
  # Mutation Output
  # ============================================================================

  object :sync_progress_payload do
    field :playthroughs, non_null(list_of(non_null(:playthrough)))
    field :events, non_null(list_of(non_null(:playback_event)))
    field :server_time, non_null(:datetime)
  end

  # ============================================================================
  # Mutations
  # ============================================================================

  object :playback_mutations do
    field :sync_progress, :sync_progress_payload do
      arg :input, non_null(:sync_progress_input)

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.sync_progress/2
    end
  end
end
