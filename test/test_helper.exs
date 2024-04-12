ExUnit.after_suite(fn _results ->
  File.rm_rf!(Ambry.Paths.uploads_folder_disk_path())
end)

ExUnit.start()
Mneme.start()
Ecto.Adapters.SQL.Sandbox.mode(Ambry.Repo, :manual)
