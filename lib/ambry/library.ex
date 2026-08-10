defmodule Ambry.Library do
  @moduledoc """
  Where the library physically lives (roadmap 3a).

  Two registries, deliberately separate because they are separate concepts:

    * **Sources** (`Ambry.Library.Source`) — watched folders audiobooks
      arrive from. Read, never written. Each carries one promise: whether
      its files can be trusted to stay (`on_import`).
    * **Library roots** (`Ambry.Library.Root`) — the folders managed audio
      is organized into. Written, never watched. Optional: a setup whose
      sources are all trusted imports nothing into a root.

  This module is also the place that answers "can these two paths share a
  hardlink?".

  ## Why more than one root is a first-class arrangement

  In production the downloads folder and the uploads folder are on two
  different NAS boxes. A hardlink cannot cross a filesystem, so no single
  root can serve both the legacy transcoded library and new hardlinked
  imports. Multiple roots merging into one logical library isn't a
  convenience here, it's the only arrangement that works.

  The consequence worth stating plainly: a same-filesystem check has to gate
  every hardlink, and it has to **fail loudly** rather than quietly falling
  back to a full copy. A silent copy doubles storage, which is the exact
  thing this phase exists to stop.

  The legacy uploads library is deliberately not registered here. It isn't
  organized by the naming template and Phase 4's reclaim owns migrating it;
  until then it keeps resolving through `Ambry.Paths` unchanged. Images
  (covers, person photos) also stay in `Ambry.Paths`' internal storage —
  they're derived, re-fetchable artifacts, not library content.
  """

  use Boundary,
    deps: [Ambry.Repo],
    exports: [Source, Root, NamingTemplate, Placement]

  import Ecto.Query

  alias Ambry.Library.Root
  alias Ambry.Library.Source
  alias Ambry.Repo

  defmodule Status do
    @moduledoc """
    What a source or root looks like on disk right now.

    Deliberately not stored: a NAS that was mounted when the row was written
    tells you nothing about whether it's mounted now, and a stale "healthy"
    is worse than no answer.
    """
    defstruct [:exists?, :directory?, :writable?, :device]
  end

  ## sources

  @doc """
  Lists sources, by name.

  Options: `:enabled`.
  """
  def list_sources(opts \\ []) do
    Source
    |> filter_by_enabled(opts[:enabled])
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  The sources discovery should scan.
  """
  def watched_sources, do: list_sources(enabled: true)

  def fetch_source(id), do: Repo.fetch(Source, id)

  def get_source!(id), do: Repo.get!(Source, id)

  def create_source(attrs), do: %Source{} |> Source.changeset(attrs) |> Repo.insert()

  def update_source(%Source{} = source, attrs) do
    source |> Source.changeset(attrs) |> Repo.update()
  end

  @doc """
  Removes a source from the registry. Never touches the files it points at.
  """
  def delete_source(%Source{} = source), do: Repo.delete(source)

  def change_source(%Source{} = source, attrs \\ %{}), do: Source.changeset(source, attrs)

  @doc """
  Records that a source was just scanned.
  """
  def mark_scanned(%Source{} = source) do
    update_source(source, %{last_scanned_at: DateTime.utc_now(:second)})
  end

  ## roots

  @doc """
  The roots managed files may be organized into, by name.
  """
  def list_roots do
    Root
    |> order_by([r], asc: r.name)
    |> Repo.all()
  end

  def fetch_root(id), do: Repo.fetch(Root, id)

  def get_root!(id), do: Repo.get!(Root, id)

  def create_root(attrs), do: %Root{} |> Root.changeset(attrs) |> Repo.insert()

  def update_root(%Root{} = root, attrs), do: root |> Root.changeset(attrs) |> Repo.update()

  @doc """
  Removes a root from the registry.

  This never touches the files it points at — deleting a row is not how an
  operator says "delete my library".
  """
  def delete_root(%Root{} = root), do: Repo.delete(root)

  def change_root(%Root{} = root, attrs \\ %{}), do: Root.changeset(root, attrs)

  @doc """
  Whether a path lies inside a registered library root.

  This is derived, never declared: nobody should have to *tell* the system a
  folder is inside the library. Import uses it to notice that bringing a
  file in would be copying it to where it already is, and adopts in place
  instead.
  """
  def inside_root?(path) when is_binary(path) do
    Enum.any?(list_roots(), fn root ->
      String.starts_with?(path <> "/", root.path <> "/")
    end)
  end

  @doc """
  Every registered path, source or root.

  Cleanup uses these as pruning stops: a registered folder's existence is
  configuration, not leftover clutter, so empty-parent pruning never removes
  one.
  """
  def registered_paths do
    Enum.map(list_sources(), & &1.path) ++ Enum.map(list_roots(), & &1.path)
  end

  ## disk

  @doc """
  Looks at a source or root on disk.

  Returns a `Status` with everything the admin UI needs to tell
  "misconfigured" from "unmounted" from "fine".
  """
  def status(%Source{path: path}), do: status(path)
  def status(%Root{path: path}), do: status(path)

  def status(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, stat} ->
        %Status{
          exists?: true,
          directory?: stat.type == :directory,
          writable?: stat.access in [:write, :read_write],
          device: stat.major_device
        }

      {:error, _reason} ->
        %Status{exists?: false, directory?: false, writable?: false, device: nil}
    end
  end

  @doc """
  Whether two paths sit on the same filesystem, and can therefore be
  hardlinked between.

  Returns `{:error, reason}` rather than `false` when the question can't be
  answered — a missing mount must not read as "different filesystem, fall
  back to copying", because copying is exactly the storage doubling this
  phase exists to prevent.
  """
  def same_filesystem?(source, destination) do
    with {:ok, source_device} <- device(source),
         {:ok, destination_device} <- device(destination) do
      {:ok, source_device == destination_device}
    end
  end

  @doc """
  The filesystem a path lives on.

  Deliberately strict about the path existing. It's tempting to walk up to
  the nearest existing ancestor so a not-yet-created destination can be asked
  about, but that turns an unmounted volume into a confident wrong answer:
  `/mnt/nas-b/library` on an unmounted `/mnt/nas-b` would report the root
  filesystem's device, and writing there fills the OS disk instead of the
  NAS. Callers ask about a registered path, which exists whenever the volume
  is mounted — that's the whole point of checking.
  """
  def device(path) do
    case File.stat(path) do
      {:ok, stat} -> {:ok, stat.major_device}
      {:error, reason} -> {:error, {reason, path}}
    end
  end

  defp filter_by_enabled(query, nil), do: query
  defp filter_by_enabled(query, enabled), do: where(query, [s], s.enabled == ^enabled)
end
