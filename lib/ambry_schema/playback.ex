defmodule AmbrySchema.Playback do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  alias AmbrySchema.Resolvers

  ## Enums

  enum :playback_event_type do
    value :start
    value :play
    value :pause
    value :seek
    value :rate_change
    value :finish
    value :abandon
    value :resume
    value :delete
  end

  enum :device_type do
    value :ios
    value :android
    value :web
  end

  enum :device_type_input do
    value :ios
    value :android
  end

  ## Output Types

  object :device do
    field :id, non_null(:id)
    field :type, non_null(:device_type)
    field :brand, :string
    field :model_name, :string
    field :browser, :string
    field :browser_version, :string
    field :os_name, :string
    field :os_version, :string
    field :app_id, :string
    field :app_version, :string
    field :app_build, :string
    field :last_seen_at, non_null(:datetime)
  end

  object :playback_event do
    field :id, non_null(:id)
    field :playthrough_id, non_null(:id)
    field :device_id, :id
    field :media_id, :id
    field :type, non_null(:playback_event_type)
    field :timestamp, non_null(:datetime)
    field :position, :float, resolve: Resolvers.resolve_decimal(:position)
    field :playback_rate, :float, resolve: Resolvers.resolve_decimal(:playback_rate)
    field :from_position, :float, resolve: Resolvers.resolve_decimal(:from_position)
    field :to_position, :float, resolve: Resolvers.resolve_decimal(:to_position)
    field :previous_rate, :float, resolve: Resolvers.resolve_decimal(:previous_rate)
  end

  ## Input Types

  input_object :device_input do
    field :id, non_null(:id)
    field :type, non_null(:device_type_input)
    field :brand, :string
    field :model_name, :string
    field :browser, :string
    field :browser_version, :string
    field :os_name, :string
    field :os_version, :string
    field :app_id, :string
    field :app_version, :string
    field :app_build, :string
  end

  input_object :playback_event_input do
    field :id, non_null(:id)
    field :playthrough_id, non_null(:id)
    field :media_id, :id
    field :type, non_null(:playback_event_type)
    field :timestamp, non_null(:datetime)
    field :position, :float
    field :playback_rate, :float
    field :from_position, :float
    field :to_position, :float
    field :previous_rate, :float
  end

  # V2 input - events only, no playthroughs needed
  input_object :sync_events_input do
    field :last_sync_time, :datetime
    field :device, non_null(:device_input)
    field :events, non_null(list_of(non_null(:playback_event_input)))
  end

  ## Mutation Output

  # V2 payload - events only
  object :sync_events_payload do
    field :events, non_null(list_of(non_null(:playback_event)))
    field :server_time, non_null(:datetime)
  end

  ## Mutations

  object :playback_mutations do
    @desc "V2 sync: events only, no playthroughs. All state is derived from events."
    field :sync_events, :sync_events_payload do
      arg :input, non_null(:sync_events_input)

      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.sync_events/2
    end
  end
end
