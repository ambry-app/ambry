defmodule Ambry.FirstTimeSetupTest do
  use Ambry.DataCase

  alias Ambry.FirstTimeSetup

  describe "disable!/0" do
    test "creates a lock file in the uploads folder" do
      assert :ok = FirstTimeSetup.disable!("test contents")

      assert File.read!(Ambry.Paths.uploads_folder_disk_path("setup.lock")) == "test contents"
    end
  end
end
