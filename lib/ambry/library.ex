defmodule Ambry.Library do
  @moduledoc """
  Where the library physically lives (roadmap 3a).

  The library the client sees is one thing; on disk it is any number of
  folders, possibly on different machines. This is the registry of those
  folders — the source folders discovery watches and the roots managed files
  are organized into — and the place that answers "can these two locations
  share a hardlink?".

  ## Why more than one root is mandatory

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
  until then it keeps resolving through `Ambry.Paths` unchanged.
  """

  use Boundary,
    deps: [Ambry.Repo],
    exports: [Location, NamingTemplate, Placement]

  import Ecto.Query

  alias Ambry.Library.Location
  alias Ambry.Repo

  defmodule Status do
    @moduledoc """
    What a location looks like on disk right now.

    Deliberately not stored: a NAS that was mounted when the row was written
    tells you nothing about whether it's mounted now, and a stale "healthy"
    is worse than no answer.
    """
    defstruct [:exists?, :directory?, :writable?, :device]
  end

  @doc """
  Lists locations, ordered by kind then name.

  Options: `:kind`, `:enabled`.
  """
  def list_locations(opts \\ []) do
    Location
    |> filter_by_kind(opts[:kind])
    |> filter_by_enabled(opts[:enabled])
    |> order_by([l], asc: l.kind, asc: l.name)
    |> Repo.all()
  end

  @doc """
  The locations discovery should scan.

  Library roots are included: files hand-placed into the tree have to surface
  somewhere, and the inbox is the only road into the library.
  """
  def watched_locations, do: list_locations(enabled: true)

  @doc """
  The roots managed files may be organized into.
  """
  def library_roots(opts \\ []), do: list_locations(Keyword.put(opts, :kind, :library_root))

  def fetch_location(id), do: Repo.fetch(Location, id)

  def get_location!(id), do: Repo.get!(Location, id)

  def create_location(attrs) do
    %Location{} |> Location.changeset(attrs) |> validate_target_root() |> Repo.insert()
  end

  def update_location(%Location{} = location, attrs) do
    location |> Location.changeset(attrs) |> validate_target_root() |> Repo.update()
  end

  @doc """
  The library root a downloads location imports into.

  With a single root the answer is obvious and the location needn't say, so a
  null `target_root_id` resolves to the only root there is. With several it
  has to be explicit — guessing would be guessing about which NAS, and
  therefore about whether hardlinking is possible at all.

  Only `:downloads` locations import anywhere; everything else is adopted in
  place, so asking is a caller error rather than a missing configuration.
  """
  @deprecated "Inputs and outputs are independent; the destination is a draft decision"
  def target_root(%Location{kind: kind}) when kind != :downloads, do: {:error, :not_importing}

  def target_root(%Location{target_root_id: id}) when is_integer(id) do
    case Repo.get(Location, id) do
      %Location{kind: :library_root} = root -> {:ok, root}
      %Location{} -> {:error, :target_not_a_root}
      nil -> {:error, :target_root_missing}
    end
  end

  def target_root(%Location{}) do
    case library_roots() do
      [root] -> {:ok, root}
      [] -> {:error, :no_library_root}
      _several -> {:error, :ambiguous_library_root}
    end
  end

  # Pairing a downloads folder with something that isn't a root would produce
  # imports landing in someone else's collection, which external custody
  # exists to promise never happens.
  defp validate_target_root(changeset) do
    case Ecto.Changeset.get_field(changeset, :target_root_id) do
      nil ->
        changeset

      id ->
        case Repo.get(Location, id) do
          %Location{kind: :library_root} ->
            changeset

          _missing_or_wrong_kind ->
            Ecto.Changeset.add_error(changeset, :target_root_id, "must be a library root")
        end
    end
  end

  @doc """
  Removes a location from the registry.

  This never touches the files it points at — for `:external_collection` that
  would break the promise of external custody, and for the others deleting a
  row is not how an operator says "delete my library".
  """
  def delete_location(%Location{} = location), do: Repo.delete(location)

  def change_location(%Location{} = location, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  @doc """
  Records that a location was just scanned.
  """
  def mark_scanned(%Location{} = location) do
    update_location(location, %{last_scanned_at: DateTime.utc_now(:second)})
  end

  @doc """
  Looks at a location on disk.

  Returns a `Status` with everything the admin UI needs to tell "misconfigured"
  from "unmounted" from "fine".
  """
  def status(%Location{path: path}), do: status(path)

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
  NAS. Callers ask about a registered location's own path, which exists
  whenever the volume is mounted — that's the whole point of checking.
  """
  def device(path) do
    case File.stat(path) do
      {:ok, stat} -> {:ok, stat.major_device}
      {:error, reason} -> {:error, {reason, path}}
    end
  end

  defp filter_by_kind(query, nil), do: query
  defp filter_by_kind(query, kind), do: where(query, [l], l.kind == ^kind)

  defp filter_by_enabled(query, nil), do: query
  defp filter_by_enabled(query, enabled), do: where(query, [l], l.enabled == ^enabled)
end
