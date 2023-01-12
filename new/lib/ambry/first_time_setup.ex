defmodule Ambry.FirstTimeSetup do
  @moduledoc """
  Context to handle first-time-setup related tasks.
  """

  alias Ambry.Paths

  @contents """
  This file is created once first-time-setup has been completed.
  Please don't delete it.
  """

  @doc """
  Disables first-time-setup, so that the redirect no longer happens.
  """
  def disable!(contents \\ @contents) do
    File.write!(Paths.uploads_folder_disk_path("setup.lock"), contents)
  end
end
