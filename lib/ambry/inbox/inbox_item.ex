defmodule Ambry.Inbox.InboxItem do
  @moduledoc """
  One candidate recording waiting to be curated into the library.

  An item references files where they landed — nothing is copied, linked, or
  organized until it's imported. `path` is the item's identity (the release
  folder, or a loose file), which is what makes rescans idempotent and keeps
  ignored items ignored.

  `path` and `files` are stored relative to the item's source, so a source
  whose mount point changes is a one-row edit. Resolve through `disk_path/1`
  and `disk_files/1`.

  **Two questions about one list.** `files` is everything under this item;
  `excluded_files` says which of them the operator took out of the audiobook.
  `files` is the ownership ledger discovery reads: a file it does not claim
  belongs to nobody, so shortening the list would hand the file back as an
  item of its own on the next scan. Use `owned_disk_files/1` for who holds
  what, `disk_files/1` for what a listener will hear.

  A replacement links a second item to a recording the library already has,
  and from then on the first describes files that are gone.
  `superseded_by_id` records that rather than working it out, since a file
  can arrive by hardlink, symlink, copy or move. A partial unique index
  enforces the other side: a recording has at most one import that has not
  been superseded.
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

    # Set on the *old* item when a replacement links a second item to one
    # recording. Nil means this item's files are what is served.
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

    # Not a status value: status is where the operator has taken this item,
    # and missing is orthogonal and reversible.
    field :missing_since, :utc_datetime
    field :probe, :map
    field :tags, :map
    field :matches, :map
    field :issue, :string

    # Derived from the draft, denormalized so the queue filters and counts in
    # SQL. `put_draft/2` is their only writer.
    field :ready, :boolean, default: false

    # Flattened for the queue's search. The `update_inbox_tsvector` trigger
    # turns this and `path` into `search_vector`, which is not declared here:
    # the trigger is its only writer.
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
  Stages a draft, keeping the denormalized `ready` and `search_text` columns
  in step. Routing every draft write through one function is what stops them
  drifting.
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

  Half a dozen places read, change and write back the whole row, so a caller
  working from a copy that has since moved must be refused rather than
  obeyed. A row lock closes the same hole, but only for callers who remember
  to take it.
  """
  def versioned(%Ecto.Changeset{} = changeset), do: optimistic_lock(changeset, :lock_version)

  @doc """
  Whether this changeset would leave the row exactly as it is.

  **Only meaningful when the changeset's data is the row as read**, since it
  compares against that and not against the database.

  `Draft`'s collections are keyless `embeds_many`, so `cast_embed` reports
  every element as replaced and a draft cast back from its own dump always
  looks changed. Comparing the applied struct tells an edit from that noise.
  """
  def unchanged?(%Ecto.Changeset{} = changeset), do: apply_changes(changeset) == changeset.data

  @doc """
  What a draft is findable by, beyond the path it was found at.

  Titles, credited names and series only. Not dates, publishers or the file's
  own tags: a search box that matches everything matches nothing.
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
  A short label for the item: the folder or file name.

  A name that states nothing but a position in a set ("1 of 5") carries the
  folder it is a part of instead.
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
  The recording's files, as absolute disk paths, in discovery order: what a
  listener will hear. Use `owned_disk_files/1` for the other question.
  """
  def disk_files(%__MODULE__{} = item), do: Enum.map(included(item), &resolve!(item, &1))

  @doc """
  Every file this item holds, excluded ones included, as absolute disk paths.

  Ownership, not playback: this is what discovery reads.
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
