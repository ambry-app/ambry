defmodule Ambry.Library do
  @moduledoc """
  Where the library physically lives.

  Two registries, deliberately separate because they are separate concepts:

    * **Sources** (`Ambry.Library.Source`) — watched folders audiobooks
      arrive from. Read, never written. A path and nothing else: how import
      brings files out of one is a fact about the *pairing* with a root, so
      it is remembered per pairing (`Ambry.Library.ImportPreference`).
    * **Library roots** (`Ambry.Library.Root`) — the folders the library's
      audio is organized into, and the only place Ambry serves from.
      Written, never watched. At least one is required to import anything.

  This module also answers "can these two paths share a hardlink?". Several
  roots is a first-class arrangement, since a hardlink cannot cross a
  filesystem and downloads and library are routinely on different volumes.
  The same-filesystem check gates every hardlink and fails loudly rather than
  falling back to a copy, which would double storage silently.

  Upload-era library files are not registered here and keep resolving through
  `Ambry.Paths`, as do images.
  """

  use Boundary,
    deps: [Ambry.Paths, Ambry.Repo],
    exports: [Source, Root, ImportPreference, NamingTemplate, Placement]

  import Ecto.Query

  alias Ambry.Library.ImportPreference
  alias Ambry.Library.Mounts
  alias Ambry.Library.Root
  alias Ambry.Library.Source
  alias Ambry.Paths
  alias Ambry.Repo

  defmodule Status do
    @moduledoc """
    What a source or root looks like on disk right now.

    Deliberately not stored: a volume mounted when the row was written says
    nothing about now. `device` and `mount` together identify what a path can
    be hardlinked with; `mount` is nil where there is no mount table.
    """
    defstruct [:exists?, :directory?, :writable?, :device, :mount]
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

  Refused with `{:error, {:referenced, %{inbox_items: n}}}` while inbox items
  still resolve their paths through it. `on_delete: :restrict` backs the same
  rule, but a count is an explanation and a constraint violation is not.
  """
  def delete_source(%Source{} = source) do
    case references_to(source) do
      %{inbox_items: 0} -> Repo.delete(source)
      counts -> {:error, {:referenced, counts}}
    end
  end

  defp references_to(%Source{id: id}) do
    %{
      inbox_items: Repo.aggregate(from(i in "inbox_items", where: i.source_id == ^id), :count)
    }
  end

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

  This never touches the files it points at. Refused with
  `{:error, {:referenced, %{media: n, media_tracks: n}}}` while recordings
  still resolve their paths through it.
  """
  def delete_root(%Root{} = root) do
    case root_references(root) do
      %{media: 0, media_tracks: 0} -> Repo.delete(root)
      counts -> {:error, {:referenced, counts}}
    end
  end

  defp root_references(%Root{id: id}) do
    %{
      media: Repo.aggregate(from(m in "media", where: m.library_root_id == ^id), :count),
      media_tracks:
        Repo.aggregate(from(t in "media_tracks", where: t.library_root_id == ^id), :count)
    }
  end

  def change_root(%Root{} = root, attrs \\ %{}), do: Root.changeset(root, attrs)

  ## remembered placement

  @doc """
  Records what an import from `source` into `root` just did.

  Called once the import has committed, not when the operator picks: what the
  next import proposes is what the last one actually did.
  """
  def remember_placement(%Source{} = source, %Root{} = root, policy) do
    attrs = %{
      source_id: source.id,
      library_root_id: root.id,
      policy: policy,
      last_used_at: DateTime.utc_now(:second)
    }

    %ImportPreference{}
    |> ImportPreference.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:policy, :last_used_at, :updated_at]},
      conflict_target: [:source_id, :library_root_id]
    )
  end

  @doc """
  What this source last did, and where — `nil` until it has imported once.

  The most recent pairing, which carries both halves of the proposal: the
  root to offer, and the policy that went with it.
  """
  def recall_placement(%Source{id: id}) do
    ImportPreference
    |> where([p], p.source_id == ^id)
    |> order_by([p], desc: p.last_used_at, desc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  The policy this pairing last used, or `nil`.

  Asked per pairing rather than per source because the answer is a fact
  about the pairing: the same downloads folder may hardlink into one root
  and have to copy into another on a different disk.
  """
  def recall_policy(%Source{id: source_id}, %Root{id: root_id}) do
    ImportPreference
    |> where([p], p.source_id == ^source_id and p.library_root_id == ^root_id)
    |> select([p], p.policy)
    |> Repo.one()
  end

  ## stored-path resolution
  #
  # A stored path is either relative to a library root (the FK says which)
  # or a legacy `/uploads/...` path with a null FK, resolved through
  # `Ambry.Paths`. These are the only two cases; anything else is refused
  # rather than guessed at.

  @doc """
  Resolves a stored path to an absolute disk path.

  Takes the root (record, id, or `nil` for the legacy uploads case) and the
  stored string. Rejects a relative path containing `..` or starting with `/`
  **before anything else**: `Path.join/2` traverses upward happily, and
  resolved paths feed `File.rm_rf`.
  """
  def resolve(nil, "/uploads/" <> _rest = web_path), do: {:ok, Paths.web_to_disk(web_path)}
  def resolve(nil, path), do: {:error, {:unresolvable, path}}

  def resolve(%Root{path: base}, relative), do: resolve_in(base, relative)

  # Inbox item paths are relative to the source they were discovered in.
  def resolve(%Source{path: base}, relative), do: resolve_in(base, relative)

  def resolve(root_id, relative) when is_integer(root_id) do
    case fetch_root(root_id) do
      {:ok, root} -> resolve(root, relative)
      {:error, :not_found} -> {:error, {:no_root, root_id}}
    end
  end

  defp resolve_in(base, relative) do
    cond do
      Path.type(relative) != :relative -> {:error, {:not_relative, relative}}
      ".." in Path.split(relative) -> {:error, {:traversal, relative}}
      true -> {:ok, Path.join(base, relative)}
    end
  end

  @doc """
  Same, raising on anything unresolvable, before a bad path reaches the
  filesystem.
  """
  def resolve!(root, path) do
    case resolve(root, path) do
      {:ok, absolute} -> absolute
      {:error, reason} -> raise "unresolvable stored path: #{inspect(reason)}"
    end
  end

  @doc """
  The stored (relative) form of an absolute path inside a location.

  Refuses a path outside the location rather than emitting `../..`.
  """
  def relativize(%Root{path: base}, absolute), do: do_relativize(base, absolute)
  def relativize(%Source{path: base}, absolute), do: do_relativize(base, absolute)

  defp do_relativize(base, absolute) do
    if String.starts_with?(absolute, base <> "/"),
      do: {:ok, Path.relative_to(absolute, base)},
      else: {:error, :outside_location}
  end

  @doc """
  The root an absolute path lives in, with its relative form.

  Longest-prefix match on a path-segment boundary. For the import boundary
  only; runtime code reads the FK rather than inferring a location.
  """
  def locate(absolute) when is_binary(absolute) do
    list_roots()
    |> Enum.filter(&String.starts_with?(absolute, &1.path <> "/"))
    |> Enum.max_by(&String.length(&1.path), fn -> nil end)
    |> case do
      nil -> {:error, :no_location}
      root -> {:ok, {root, Path.relative_to(absolute, root.path)}}
    end
  end

  @doc """
  Every registered path, source or root.

  Cleanup uses these as pruning stops: a registered folder is configuration,
  not leftover clutter.
  """
  def registered_paths do
    Enum.map(list_sources(), & &1.path) ++ Enum.map(list_roots(), & &1.path)
  end

  @doc """
  Every registered location Ambry currently cannot read, with why.

  A disabled source is skipped, since it is not being scanned on purpose;
  roots are always checked. Reads the filesystem, once per location.
  """
  def unreachable_locations do
    sources = Enum.map(list_sources(enabled: true), &{:source, &1})
    roots = Enum.map(list_roots(), &{:root, &1})

    (sources ++ roots)
    |> Enum.flat_map(fn {kind, location} ->
      case trouble(kind, status(location)) do
        nil -> []
        trouble -> [%{kind: kind, name: location.name, path: location.path, trouble: trouble}]
      end
    end)
  end

  # Imports write into roots and only read from sources, so a read-only mount
  # is a problem for one and unremarkable for the other.
  defp trouble(_kind, %Status{exists?: false}), do: :missing
  defp trouble(_kind, %Status{directory?: false}), do: :not_a_directory
  defp trouble(:root, %Status{writable?: false}), do: :read_only
  defp trouble(_kind, _fine), do: nil

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
          device: stat.major_device,
          mount: mount_id(path)
        }

      {:error, _reason} ->
        %Status{exists?: false, directory?: false, writable?: false, device: nil, mount: nil}
    end
  end

  defp mount_id(path) do
    with {:ok, mounts} <- Mounts.read(),
         {:ok, mount} <- Mounts.mount_of(path, mounts) do
      mount.id
    else
      _unavailable -> nil
    end
  end

  @doc """
  Whether two paths can be hardlinked between.

  Two checks, because `link(2)` refuses in two ways and each is invisible to
  the other test:

    * **different `st_dev`** — different filesystems, and also btrfs
      subvolumes, which share a mount but carry their own device;
    * **same `st_dev`, different mounts** — two mounts of one NFS export
      share a superblock and the kernel still refuses to link across them.

  Returns `{:error, reason}` rather than `false` when the question cannot be
  answered: "I couldn't tell" must not read as "copy instead".
  """
  def same_filesystem?(source, destination) do
    with {:ok, source_device} <- device(source),
         {:ok, destination_device} <- device(destination) do
      if source_device == destination_device,
        do: same_mount?(source, destination),
        else: {:ok, false}
    end
  end

  defp same_mount?(source, destination) do
    case Mounts.read() do
      {:ok, mounts} ->
        with {:ok, source_mount} <- Mounts.mount_of(source, mounts),
             {:ok, destination_mount} <- Mounts.mount_of(destination, mounts) do
          {:ok, source_mount.id == destination_mount.id}
        end

      # No mountinfo (not Linux): device equality is the best answer there is.
      :unavailable ->
        {:ok, true}
    end
  end

  @doc """
  The filesystem a path lives on.

  Deliberately strict about the path existing: an unmounted volume's mount
  point reports the root filesystem's device, and writing there fills the OS
  disk. Callers ask about a registered path.
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
