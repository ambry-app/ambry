defmodule Ambry.Accounts.UserToken do
  @moduledoc """
  Used for password resets and email confirmations.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Ambry.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  # It is very important to keep the reset password token expiry short,
  # since someone with access to the email may take over the account.
  @reset_password_validity_in_days 1
  @confirm_validity_in_days 7
  @change_email_validity_in_days 7
  @invitation_validity_in_days 7
  @session_validity_in_days 365

  schema "users_tokens" do
    belongs_to :user, Ambry.Accounts.User

    field :token, :binary
    field :context, :string
    field :sent_to, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a token to be stored in a signed place, such as a session or a
  cookie. Being signed, it needs no hashing.

  Stored in the database as well, because Phoenix' own session cookies are
  signed rather than persisted and so are valid indefinitely. Storing them is
  what lets an individual session be expired.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  Checks the token and returns the query that looks its user up.

  Valid if it matches the stored value and has not expired
  (`@session_validity_in_days`).
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.

  The token goes to the email and the hash to the database, so read-only
  access to the database cannot be turned into access to the application. A
  user changing their email invalidates the tokens sent to the old one.
  """
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Checks the token and returns the query that looks its user up.

  Valid if it matches its stored hash, the user's email has not changed, and
  it is inside the validity period for its context ("confirm" or
  "reset_password"). For a change of email see
  `verify_change_email_token_query/2`.
  """
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^days, "day") and token.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  defp days_for_context("confirm"), do: @confirm_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days
  defp days_for_context("invitation"), do: @invitation_validity_in_days

  @doc """
  Checks a change-of-email token and returns the query that looks its user up.

  Unlike `verify_email_token_query/2` it does not require the email to be
  unchanged, which is the whole point. Valid if it matches its stored hash and
  has not expired (`@change_email_validity_in_days`); the context must start
  with "change:".
  """
  def verify_change_email_token_query(token, "change:" <> _rest = context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Returns the token struct for the given token value and context.
  """
  def by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Gets all tokens for the given user for the given contexts.
  """
  def by_user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end
end
