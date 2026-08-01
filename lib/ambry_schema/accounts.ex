defmodule AmbrySchema.Accounts do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  alias AmbrySchema.Resolvers

  object :user do
    field :email, non_null(:string)
    field :admin, non_null(:boolean)
    field :confirmed_at, :datetime

    field :inserted_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end

  object :account_queries do
    field :me, :user do
      middleware AmbrySchema.AuthMiddleware

      resolve &Resolvers.current_user/2
    end
  end
end
