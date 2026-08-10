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

  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Work

  @primary_key false

  embedded_schema do
    embeds_one :work, Work, on_replace: :update
    embeds_one :recording, Recording, on_replace: :update
    embeds_one :destination, Destination, on_replace: :update

    # The humans this import will create or reuse, one record each. Credits at
    # both levels reference them by key, which is what makes an author who
    # reads their own book one person rather than two kept in step by hand.
    embeds_many :people, PersonDecision, on_replace: :delete

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
    |> cast_embed(:people)
  end

  @doc """
  Every decision still needing a human, in the order the form presents them.

  Returns a list of `%{section:, label:, state:}`. Empty means importable —
  that is the whole invariant, and it is the only thing anything else should
  ask.
  """
  def unresolved(nil), do: [%{section: :draft, label: "Not yet prepared", state: :missing}]

  def unresolved(%__MODULE__{} = draft) do
    stale(draft) ++ work(draft) ++ recording(draft) ++ people(draft) ++ destination(draft)
  end

  # Asked once per human rather than once per credit. A self-narrated book
  # reported the same outstanding person twice when the credits each owned
  # their own copy — the invariant counts decisions, and one human is one
  # decision.
  defp people(%__MODULE__{people: people}) do
    people
    |> Enum.reject(&PersonDecision.resolved?/1)
    |> Enum.map(
      &%{
        section: :people,
        label: "Person: #{PersonDecision.label(&1)}",
        state: PersonDecision.state(&1)
      }
    )
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
  One person by key, or nil.
  """
  def person(nil, _key), do: nil

  def person(%__MODULE__{people: people}, key), do: Enum.find(people, &(&1.key == key))

  @doc """
  The people a credit is backed by, in the order it lists them.

  A key with no decision behind it is skipped rather than crashing: a draft is
  operator input held in jsonb, and a dangling reference is a data problem to
  render as an incomplete credit, not a 500 on the form.
  """
  def people_for(draft, %Credit{} = credit),
    do: credit.person_keys |> Enum.map(&person(draft, &1)) |> Enum.reject(&is_nil/1)

  @doc """
  Which credits reference each person, so the form can say where they appear.

  Returns `%{key => [%{kind:, section:, index:, name:}]}`. This is display
  only — it is derived from the credits every time rather than stored, because
  a second copy of "who is where" is exactly the thing that used to drift.
  """
  def appearances(nil), do: %{}

  def appearances(%__MODULE__{} = draft) do
    for {kind, section, index, credit} <- credits(draft),
        credit.mode == :create,
        key <- credit.person_keys,
        reduce: %{} do
      acc ->
        place = %{kind: kind, section: section, index: index, name: credit.name}
        Map.update(acc, key, [place], &(&1 ++ [place]))
    end
  end

  defp credits(%__MODULE__{} = draft) do
    tagged(draft.work && draft.work.authors, :author, "work") ++
      tagged(draft.recording && draft.recording.narrators, :narrator, "recording")
  end

  defp tagged(nil, _kind, _section), do: []

  defp tagged(credits, kind, section) do
    credits |> Enum.with_index() |> Enum.map(fn {c, i} -> {kind, section, i, c} end)
  end

  @doc """
  Every person key the credits currently reference, in form order.

  What `Seed` reconciles against: a person nobody credits any more has no
  reason to stay on the form, and a credit naming somebody new needs a
  decision minting for them.
  """
  def referenced_keys(%__MODULE__{} = draft) do
    for {_kind, _section, _index, credit} <- credits(draft),
        credit.mode == :create,
        key <- credit.person_keys,
        uniq: true,
        do: key
  end

  @doc """
  Whether a human has answered anything in this draft yet.

  What tells "matched but untouched" from "the operator has been working on
  it", which is the difference between a draft that may be thrown away and
  rebuilt from fresh evidence and one that may only be re-derived around what
  they decided. A retry that finally reaches a provider needs the first: its
  new record isn't *ticked*, so re-deriving from the ticked set would ignore
  it entirely and the retry would buy nothing.
  """
  def curated?(nil), do: false

  def curated?(%__MODULE__{} = draft) do
    Enum.any?(fields(draft), &(&1 && &1.curated)) or
      Enum.any?(credits(draft), fn {_kind, _section, _index, credit} -> credit.curated end) or
      Enum.any?((draft.work && draft.work.series) || [], & &1.curated) or
      Enum.any?(draft.people, & &1.curated) or
      # Answering the identity question and ticking records are curation too.
      # Both were missed here, so a draft whose only human input was either
      # one was rebuilt wholesale by the next background re-match.
      (draft.work && (draft.work.curated or draft.work.evidence_curated)) == true or
      (draft.recording && draft.recording.evidence_curated) == true
  end

  defp fields(%__MODULE__{work: work, recording: recording}) do
    work_fields = if work, do: [work.title, work.published, work.published_format], else: []

    recording_fields =
      if recording,
        do: [
          recording.title,
          recording.published,
          recording.published_format,
          recording.publisher,
          recording.description,
          recording.cover
        ],
        else: []

    work_fields ++ recording_fields
  end

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
      length(draft.people) + destination_total(draft.destination)
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
