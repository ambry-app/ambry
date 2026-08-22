defmodule Ambry.Inbox.InboxItem do
  @moduledoc """
  One candidate recording waiting to be curated into the library.

  An item references files where they landed — nothing is copied, linked, or
  organized until it's imported. `path` is the item's identity (the release
  folder, or a loose file), which is what makes rescans idempotent and keeps
  ignored items ignored.

  `path` and `files` are stored relative to the item's source, so a source
  whose mount point changes is a one-row edit and every queued item — and
  the operator decisions staged on it — survives the move. Resolve through
  `disk_path/1` and `disk_files/1`, never by joining the columns against
  anything directly.

  ## Two questions about one list

  `files` is everything under this item, and `excluded_files` says which of
  them the operator took out of the audiobook — a release that ships the same
  part twice, which no rule can spot and only a listener would notice.

  They are separate columns because they answer to different things.
  **`files` is the ownership ledger discovery reads**: a file it doesn't
  claim belongs to nobody, so the next hourly scan makes it an inbox item of
  its own, and shortening the list to exclude a file would mean it came back
  every hour, forever. So the item keeps holding it and says it isn't in the
  recording.

  Which one a caller wants is not a detail: `owned_disk_files/1` for who
  holds what, `disk_files/1` for what a listener will hear.

  Every item has a source. There is no other way in, which is what makes
  the relative form an invariant rather than a convention.

  ## An imported item can stop being the one that counts

  A replacement links a second item to a recording the library already has,
  and from then on the first item describes files that are gone: the
  replacement deleted the library copy it produced, and if the placement was
  a `move` its source went at import time. `superseded_by_id` is how that is
  known, and it has to be *recorded* rather than worked out — a file can
  arrive by hardlink, symlink, copy or move, so there is no comparison that
  answers it for every import.

  The rule it records is a fact about the write path: a replacement is the
  only way a second item comes to name one recording, so the item that
  linked last is the live one. A partial unique index enforces the other
  side of it — a recording has at most one import that has not been
  superseded.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.ReleaseName
  alias Ambry.Library
  alias Ambry.Library.Source
  alias Ambry.Media.Media
  alias Ambry.Repo

  @statuses [:pending, :ignored, :imported]

  schema "inbox_items" do
    belongs_to :media, Media

    # The import that replaced this one. Set on the *old* item when a
    # replacement links a second item to one recording, which is the only way
    # two items come to name the same one. Nil means this item's files are
    # what the recording is served from — see the moduledoc.
    belongs_to :superseded_by, __MODULE__

    # The watched folder this was found in, and the base its `path` and
    # `files` are relative to.
    belongs_to :source, Source

    field :path, :string

    # Everything under this item, and which of it isn't part of the
    # recording. See the moduledoc: two questions, two lists.
    field :files, {:array, :string}, default: []
    field :excluded_files, {:array, :string}, default: []
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :probe, :map
    field :tags, :map
    field :matches, :map
    field :issue, :string

    # Derived from the draft, denormalized so the queue filters and counts in
    # SQL. `put_draft/2` is their only writer.
    field :ready, :boolean, default: false

    # What the draft says this item is, flattened for the queue's search. The
    # `update_inbox_tsvector` trigger turns this and `path` into
    # `search_vector`; nothing reads this column directly.
    # `search_vector` itself is not declared: nothing in Elixir reads a
    # tsvector, the trigger is its only writer, and `Ambry.Search.Record`
    # leaves its own out for the same reason.
    field :search_text, :string

    # Bumped by every write, and checked by every write against the value the
    # writer read. See `versioned/1`.
    field :lock_version, :integer, default: 1

    embeds_one :draft, Draft, on_replace: :update

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(inbox_item, attrs) do
    inbox_item
    |> cast(attrs, [
      :path,
      :files,
      :excluded_files,
      :status,
      :probe,
      :tags,
      :matches,
      :issue,
      :media_id,
      :source_id
    ])
    |> validate_required([:path, :status, :source_id])
    |> foreign_key_constraint(:source_id)
    |> unique_constraint(:path)
  end

  @doc """
  Stages a draft, keeping the denormalized `ready` flag in step.

  Readiness is *defined* by `Draft.resolved?/1` and merely *stored* here, and
  the same goes for `search_text`. Routing every draft write through one
  function is what stops either column drifting away from the draft — there
  is no second place that may set them.

  `search_text` is built here rather than in the trigger on purpose. The
  draft is a deep embedded structure — fields wrapping values, credits
  referencing people by key — and SQL reaching into that JSON would be a
  second copy of its shape, going stale the first time the shape changed.
  """
  def put_draft(inbox_item, attrs) do
    changeset =
      inbox_item
      |> cast(%{draft: attrs}, [])
      |> cast_embed(:draft)

    draft = fetch_field!(changeset, :draft)

    changeset
    |> put_change(:ready, Draft.resolved?(draft))
    |> put_change(:search_text, search_text(draft))
  end

  @doc """
  The last step of every write to this table.

  ## Why a version

  An item is read, changed and written back from half a dozen places — the
  form, discovery, probing, matching, the post-import sweeps — and several of
  them run at once. All of them write the whole row, so the second to arrive
  overwrites whatever the first decided, and nothing anywhere says so.
  Production, 2026-08-20: the operator answered "this replaces audiobook 108"
  and a sibling import's sweep, holding a copy of the row read seconds
  earlier, put "a new audiobook" back. The import then refused an item whose
  form showed nothing wrong.

  So the row carries a version, every write bumps it, and every write demands
  the version it read. A caller working from a copy that has since moved is
  refused rather than obeyed. `Ambry.Inbox.Lookup` learned this once for
  `matches` and closed it with a row lock; a lock each caller has to remember
  to take is a lock the next caller forgets, which is precisely how it grew
  back on `draft`. This is the same rule made structural.
  """
  def versioned(%Ecto.Changeset{} = changeset), do: optimistic_lock(changeset, :lock_version)

  @doc """
  Whether this changeset would leave the row exactly as it is.

  **Only meaningful when the changeset's data is the row as read** — it
  compares against that, not against the database — so it belongs to callers
  that just read the row themselves, under the lock.

  It exists because of a quirk that would otherwise make every version bump
  meaningless. `Draft`'s collections are keyless `embeds_many`, so
  `cast_embed` cannot tell an incoming element from the one already there and
  reports every element as replaced: a draft cast back from its own dump is
  always "changed". The post-import sweeps — which mostly find nothing to
  relink — were therefore rewriting every draft they touched, on every
  import. Versioned, that would bump rows nobody edited and send the
  operator's open form stale for no reason at all.

  Comparing the applied struct is what tells an edit from that noise, and it
  is exact: equal structs mean equal jsonb.
  """
  def unchanged?(%Ecto.Changeset{} = changeset), do: apply_changes(changeset) == changeset.data

  @doc """
  What a draft is findable by, beyond the path it was found at.

  The point of the whole column: an item whose folder is
  `01 Angels and Demons.m4b` is findable by "Dan Brown", which no amount of
  matching on the path can do.

  Titles, credited names and series only — the things somebody would type
  looking for this item. Not dates, not publishers, not the file's own tags:
  a search box that matches everything matches nothing.
  """
  def search_text(nil), do: nil

  def search_text(%Draft{} = draft) do
    work = draft.work
    recording = draft.recording

    [
      work && Field.value(work.title),
      recording && Field.value(recording.title),
      credited(work && work.authors),
      credited(recording && recording.narrators),
      Enum.map(draft.people || [], &Field.value(&1.name)),
      Enum.map((work && work.series) || [], & &1.name)
    ]
    |> List.flatten()
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.uniq()
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  defp credited(nil), do: []
  defp credited(credits), do: Enum.map(credits, & &1.name)

  @doc """
  A short label for the item: the folder or file name, which is usually the
  release name and the most recognizable thing about it.

  The exception is a name that states nothing but a position in a set: an item split out of "The Way of Kings/1 of 5" is called "1 of 5",
  which in a queue of five siblings and 300 other releases says nothing at
  all. Those carry the folder they are a part of.
  """
  def name(%__MODULE__{path: path}) do
    base = Path.basename(path)

    if ReleaseName.part_folder?(base),
      do: Path.join(Path.basename(Path.dirname(path)), base),
      else: base
  end

  @doc """
  The item's absolute path on disk.
  """
  def disk_path(%__MODULE__{path: path} = item), do: resolve!(item, path)

  @doc """
  The recording's files, as absolute disk paths, in discovery order.

  What a listener will hear, which is what everything downstream of curation
  means by "the files": the probe measures these, the draft is seeded from
  them, and import places these and writes them as tracks. Use
  `owned_disk_files/1` for the other question — see the moduledoc.
  """
  def disk_files(%__MODULE__{} = item), do: Enum.map(included(item), &resolve!(item, &1))

  @doc """
  Every file this item holds, excluded ones included, as absolute disk paths.

  Ownership, not playback. Discovery reads this: a file the queue no longer
  claims belongs to nobody, and the next scan hands it an inbox item of its
  own. Excluding a file must therefore never let go of it.
  """
  def owned_disk_files(%__MODULE__{files: files} = item), do: Enum.map(files, &resolve!(item, &1))

  @doc """
  The stored form of the recording's files: everything held, less what the
  operator took out.
  """
  def included(%__MODULE__{files: files, excluded_files: excluded}), do: files -- excluded

  @doc """
  Whether this file is held by the item but not part of the recording.
  """
  def excluded?(%__MODULE__{excluded_files: excluded}, file), do: file in excluded

  # Raising is deliberate: these paths get probed and placed, and a path that
  # can't resolve must never quietly become a relative one.
  defp resolve!(%__MODULE__{} = item, path) do
    case Library.resolve(item_source(item), path) do
      {:ok, absolute} -> absolute
      {:error, reason} -> raise "unresolvable inbox path: #{inspect(reason)}"
    end
  end

  defp item_source(%__MODULE__{source: %Source{} = source}), do: source
  defp item_source(%__MODULE__{source_id: id}), do: Repo.get!(Source, id)
end
