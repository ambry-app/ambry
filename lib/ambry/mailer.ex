defmodule Ambry.Mailer do
  @moduledoc false

  use Boundary
  use Swoosh.Mailer, otp_app: :ambry
end
