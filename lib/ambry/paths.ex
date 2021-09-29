defmodule Ambry.Paths do
  @moduledoc """
  Helpers for paths, like the uploads path.
  """

  def uploads_path do
    Application.fetch_env!(:ambry, :uploads_path)
  end
end
