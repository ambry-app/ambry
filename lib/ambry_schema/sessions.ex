defmodule AmbrySchema.Sessions do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  alias AmbrySchema.Resolvers

  object :session_mutations do
    payload field :create_session do
      input do
        field :email, non_null(:string)
        field :password, non_null(:string)
      end

      output do
        field :token, non_null(:string)
        field :user, non_null(:user)
      end

      resolve &Resolvers.create_session/2
    end

    payload field :delete_session do
      output do
        field :deleted, non_null(:boolean)
      end

      resolve &Resolvers.delete_session/2
    end
  end
end
