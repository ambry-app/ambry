defmodule Ambry.Accounts.EmailSender do
  @moduledoc """
  Oban worker for sending account-related emails asynchronously.
  """

  use Oban.Worker

  alias Ambry.Accounts
  alias Ambry.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "action" => "deliver_confirmation_instructions",
          "user_id" => user_id,
          "url" => url
        }
      }) do
    user = Accounts.get_user!(user_id)
    UserNotifier.deliver_confirmation_instructions(user, url)
  end

  def perform(%Oban.Job{
        args: %{
          "action" => "deliver_reset_password_instructions",
          "user_id" => user_id,
          "url" => url
        }
      }) do
    user = Accounts.get_user!(user_id)
    UserNotifier.deliver_reset_password_instructions(user, url)
  end

  def perform(%Oban.Job{
        args: %{
          "action" => "deliver_update_email_instructions",
          "user_id" => user_id,
          "url" => url
        }
      }) do
    user = Accounts.get_user!(user_id)
    UserNotifier.deliver_update_email_instructions(user, url)
  end
end
