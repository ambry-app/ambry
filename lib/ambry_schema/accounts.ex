defmodule AmbrySchema.Accounts do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias AmbrySchema.Resolvers

  object :user do
    field :email, non_null(:string)
    field :admin, non_null(:boolean)
    field :confirmed_at, :naive_datetime

    field :loaded_player_state, :player_state, resolve: dataloader(Resolvers)

    field :inserted_at, non_null(:naive_datetime)
    field :updated_at, non_null(:naive_datetime)
  end

  object :account_queries do
    field :me, :user do
      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.current_user/2
    end
  end
end
