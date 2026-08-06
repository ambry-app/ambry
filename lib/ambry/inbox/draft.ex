defmodule Ambry.Inbox.Draft do
  @moduledoc """
  The staged import: everything this release will become, before any of it is
  real.

  ## The invariant

  **An import is a tree of decisions, and import is possible iff every
  decision is resolved.** `unresolved/1` is the single expression of that —
  the import button, the queue's Ready badge and the tests all read it, so
  they cannot disagree about whether an item is finished.

  Nothing about an import may be implicit. A field nobody proposed is a
  `:missing` decision the operator can see, not a surprise at approval time;
  a field two sources disagree about is `:ambiguous` rather than silently
  first-wins. The corollary is that the form must never render an import
  button that fails.

  ## Why an embed, not staging tables

  Held as an embed in a jsonb column on `inbox_items`, so half-curated
  discoveries never touch the library tables (3b's reason for a separate
  inbox table in the first place). Embedded schemas buy changesets,
  validation and `inputs_for`, which is what makes the form ordinary nested
  LiveView rather than hand-rolled jsonb poking. Real staging tables would
  add referential integrity to data whose entire point is that it isn't real
  yet.

  ## Rescans never touch a draft

  Discovery updates an item's `files`, `probe` and `tags` and stops there. A
  curated choice is not something a background scan may overwrite; where the
  evidence genuinely moved, the affected decisions are marked stale rather
  than rewritten (see `Ambry.Inbox.Draft.Seed.restale/2`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.PersonRef
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Work

  @primary_key false

  embedded_schema do
    embeds_one :work, Work, on_replace: :update
    embeds_one :recording, Recording, on_replace: :update
    embeds_one :destination, Destination, on_replace: :update

    # Bumped when discovery sees the underlying files change, so a draft built
    # against evidence that has since moved can say so instead of quietly
    # describing a file that isn't there any more.
    field :evidence, :string
    field :stale, :boolean, default: false
  end

  @doc false
  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:evidence, :stale])
    |> cast_embed(:work)
    |> cast_embed(:recording)
    |> cast_embed(:destination)
  end

  @doc """
  Every decision still needing a human, in the order the form presents them.

  Returns a list of `%{section:, label:, state:}`. Empty means importable —
  that is the whole invariant, and it is the only thing anything else should
  ask.
  """
  def unresolved(nil), do: [%{section: :draft, label: "Not yet prepared", state: :missing}]

  def unresolved(%__MODULE__{} = draft) do
    stale(draft) ++ work(draft) ++ recording(draft) ++ destination(draft)
  end

  # Absent means nothing was staged about the bytes, which for an adopt-in-
  # place item is the normal case rather than an omission.
  defp destination(%__MODULE__{destination: nil}), do: []

  defp destination(%__MODULE__{destination: destination}) do
    if Destination.resolved?(destination),
      do: [],
      else: [
        %{
          section: :destination,
          label: "Which library root to import into",
          state: Destination.state(destination)
        }
      ]
  end

  defp stale(%__MODULE__{stale: true}),
    do: [%{section: :draft, label: "The files changed since this was prepared", state: :stale}]

  defp stale(%__MODULE__{}), do: []

  defp work(%__MODULE__{work: nil}), do: [%{section: :work, label: "Which book", state: :missing}]

  defp work(%__MODULE__{work: work}), do: Work.unresolved(work)

  defp recording(%__MODULE__{recording: nil}),
    do: [%{section: :recording, label: "Which recording", state: :missing}]

  defp recording(%__MODULE__{recording: recording}), do: Recording.unresolved(recording)

  @doc """
  Whether this draft can be imported.
  """
  def resolved?(draft), do: unresolved(draft) == []

  @doc """
  Which credits each pending person is behind, keyed by `PersonRef.key/1`.

  Almost always one, and the interesting answer is two: an author who reads
  their own book is one human with an Author identity and a Narrator identity,
  and the two credits proposing to create them have no idea about each other.
  Approval already resolves them to one Person — this is what lets the form
  *say* so before the operator presses import, which is the difference between
  a sensible default and a surprise.
  """
  def sharing(nil), do: %{}

  def sharing(%__MODULE__{} = draft) do
    (tagged(draft.work && draft.work.authors, :author) ++
       tagged(draft.recording && draft.recording.narrators, :narrator))
    |> Enum.filter(fn {_kind, credit} -> credit.mode == :create end)
    |> Enum.flat_map(fn {kind, credit} -> Enum.map(credit.people, &{PersonRef.key(&1), kind}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {key, kinds} -> {key, Enum.uniq(kinds)} end)
  end

  defp tagged(nil, _kind), do: []
  defp tagged(credits, kind), do: Enum.map(credits, &{kind, &1})

  @doc """
  How far along the operator is, for the queue and the form header.
  """
  def progress(nil), do: %{resolved: 0, total: 0}

  def progress(%__MODULE__{} = draft) do
    outstanding = length(unresolved(draft))
    %{resolved: total(draft) - outstanding, total: total(draft)}
  end

  # Every decision the tree contains, resolved or not. Counted rather than
  # stored: a stored total is a second source of truth waiting to drift from
  # the first.
  defp total(%__MODULE__{} = draft) do
    work_total(draft.work) + recording_total(draft.recording) +
      destination_total(draft.destination)
  end

  defp destination_total(nil), do: 0
  defp destination_total(%Destination{custody: :external}), do: 0
  defp destination_total(%Destination{}), do: 1

  defp work_total(nil), do: 1

  defp work_total(%Work{mode: :link} = work), do: 1 + length(work.series)

  defp work_total(%Work{} = work) do
    1 + 3 + length(work.authors) + length(work.series)
  end

  defp recording_total(nil), do: 1
  defp recording_total(%Recording{} = recording), do: 1 + 5 + length(recording.narrators)
end
