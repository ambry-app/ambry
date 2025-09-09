defmodule Ambry.Accounts do
  @moduledoc """
  The Accounts context.
  """

  use Boundary,
    deps: [
      Ambry.Mailer,
      Ambry.Media,
      Ambry.Repo
    ],
    exports: [User]

  import Ecto.Query, warn: false

  alias Ambry.Accounts.SendEmail
  alias Ambry.Accounts.User
  alias Ambry.Accounts.UserFlat
  alias Ambry.Accounts.UserToken
  alias Ambry.Repo

  ## Database getters

  @doc """
  Returns a limited list of users and whether or not there are more.

  By default, it will limit to the first 10 results. Supply `offset` and `limit`
  to change this. You can also optionally filter by giving a map with these
  supported keys:

    * `:search` - String: full-text search on names and aliases.
    * `:admin` - Boolean.
    * `:confirmed` - Boolean.

  `order` should be a valid atom key, or a tuple like `{:email, :desc}`.

  ## Examples

      iex> list_users()
      {[%UserFlat{}, ...], true}

  """
  def list_users(offset \\ 0, limit \\ 10, filters \\ %{}, order \\ :email) do
    over_limit = limit + 1

    users =
      offset
      |> UserFlat.paginate(over_limit)
      |> UserFlat.filter(filters)
      |> UserFlat.order(order)
      |> Repo.all()

    users_to_return = Enum.slice(users, 0, limit)

    {users_to_return, users != users_to_return}
  end

  @doc """
  Returns the number of users.

  ## Examples

      iex> count_users()
      1

  """
  @spec count_users :: integer()
  def count_users do
    Repo.aggregate(User, :count)
  end

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user \\ %User{}, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transact(user_email_multi(user, email, context)) do
      :ok
    else
      _error -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
      {:ok, _token}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    Repo.transact(fn ->
      {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")
      url = update_email_url_fun.(encoded_token)

      with {:ok, _token} <- Repo.insert(user_token),
           {:ok, _job} <- send_update_email_instructions_async(user, url) do
        {:ok, encoded_token}
      end
    end)
  end

  defp send_update_email_instructions_async(%User{} = user, url) do
    %{user_id: user.id, action: "deliver_update_email_instructions", url: url}
    |> SendEmail.new()
    |> Oban.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transact()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _actions_applied} -> {:error, changeset}
    end
  end

  @doc """
  Updates the user's loaded player state.

  ## Examples

      iex> update_user_loaded_player_state(user, 1)
      {:ok, %User{}}
  """
  def update_user_loaded_player_state(user, player_state_id) do
    changeset = User.loaded_player_state_changeset(user, player_state_id)

    Repo.update(changeset)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      Repo.transact(fn ->
        {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
        url = confirmation_url_fun.(encoded_token)

        with {:ok, _token} <- Repo.insert(user_token),
             {:ok, _job} <- send_confirmation_email_async(user, url) do
          {:ok, encoded_token}
        end
      end)
    end
  end

  defp send_confirmation_email_async(%User{} = user, url) do
    %{user_id: user.id, action: "deliver_confirmation_instructions", url: url}
    |> SendEmail.new()
    |> Oban.insert()
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transact(confirm_user_multi(user)) do
      {:ok, user}
    else
      _error -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    Repo.transact(fn ->
      {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
      url = reset_password_url_fun.(encoded_token)

      with {:ok, _token} <- Repo.insert(user_token),
           {:ok, _job} <- send_reset_password_email_async(user, url) do
        {:ok, encoded_token}
      end
    end)
  end

  defp send_reset_password_email_async(%User{} = user, url) do
    %{user_id: user.id, action: "deliver_reset_password_instructions", url: url}
    |> SendEmail.new()
    |> Oban.insert()
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _error -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transact()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _changes_so_far} -> {:error, changeset}
    end
  end

  @doc """
  Promotes a user to be an admin.

  ## Examples

      iex> promote_user_to_admin(user)
      {:ok, %User{admin: true}}
  """
  def promote_user_to_admin(user) do
    user
    |> User.promote_to_admin_changeset()
    |> Repo.update()
  end

  @doc """
  Demote a user from being an admin.

  ## Examples

      iex> demote_user_from_admin(user)
      {:ok, %User{admin: false}}
  """
  def demote_user_from_admin(user) do
    user
    |> User.demote_from_admin_changeset()
    |> Repo.update()
  end

  @doc """
  Returns true if at least one admin user exists.

  ## Examples

      iex> admin_exists?()
      true
  """
  def admin_exists? do
    Repo.aggregate(from(u in User, where: u.admin), :count) > 0
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      :ok
  """
  def delete_user(%User{} = user) do
    {:ok, _user} = Repo.delete(user)

    :ok
  end

  ## User invitations

  @doc ~S"""
  Delivers a user invitation email to the given email address.

  This will create a new unconfirmed user account and send an invitation email.

  ## Examples

      iex> deliver_user_invitation("new@example.com", &url(~p"/users/accept_invitation/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_invitation("new@example.com", &url(~p"/users/accept_invitation/#{&1}"))
      {:error, :not_admin}

  """
  def deliver_user_invitation(email, accept_invitation_url_fun)
      when is_function(accept_invitation_url_fun, 1) do
    Repo.transact(fn ->
      with {:ok, user} <- create_user_for_invitation(email),
           {encoded_token, user_token} = UserToken.build_email_token(user, "invitation"),
           {:ok, _token} <- Repo.insert(user_token),
           url = accept_invitation_url_fun.(encoded_token),
           {:ok, _job} <- send_invitation_email_async(user, url) do
        {:ok, encoded_token}
      end
    end)
  end

  defp create_user_for_invitation(email) do
    %User{}
    |> User.invitation_changeset(%{email: email})
    |> Repo.insert()
  end

  defp send_invitation_email_async(%User{} = user, url) do
    %{user_id: user.id, action: "deliver_invitation_email", url: url}
    |> SendEmail.new()
    |> Oban.insert()
  end

  @doc """
  Gets a user by invitation token.

  ## Examples

      iex> get_user_by_invitation_token("validtoken")
      %User{}

      iex> get_user_by_invitation_token("invalidtoken")
      nil

  """
  def get_user_by_invitation_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "invitation"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _error -> nil
    end
  end

  @doc """
  Accepts a user invitation by setting their password and confirming their account.

  ## Examples

      iex> accept_user_invitation(user, %{password: "new password", password_confirmation: "new password"})
      {:ok, %User{}}

      iex> accept_user_invitation(user, %{password: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def accept_user_invitation(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.accept_invitation_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transact()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _changes_so_far} -> {:error, changeset}
    end
  end
end
