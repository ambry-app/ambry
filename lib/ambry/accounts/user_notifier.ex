defmodule Ambry.Accounts.UserNotifier do
  @moduledoc """
  Delivers various kinds of emails to users.
  """

  import Swoosh.Email

  alias Ambry.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    from_address = Application.get_env(:ambry, :from_address, "ambry@example.com")

    email =
      new()
      |> to(recipient)
      |> from({"Ambry", from_address})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", """

    ==============================

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to accept a user invitation.
  """
  def deliver_invitation_email(user, url) do
    deliver(user.email, "Invitation to join Ambry", """

    ==============================

    Hi #{user.email},

    You've been invited to join Ambry. You can set up your account by visiting the URL below:

    #{url}

    If you weren't expecting an invitation, please ignore this.

    ==============================
    """)
  end
end
