defmodule Ambry.FirstTimeSetup do
  @moduledoc """
  Context to handle first-time-setup related tasks.
  """

  alias Ambry.Paths

  @doc """
  Disables first-time-setup, so that the redirect no longer happens.
  """
  def disable! do
    File.write!(Paths.uploads_folder_disk_path("setup.lock"), """
    This file is created once first-time-setup has been completed.
    Please don't delete it.
    """)
  end
end
