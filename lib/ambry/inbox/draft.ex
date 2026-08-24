defmodule Ambry.Inbox.Draft do
  @moduledoc """
  The staged import: everything this release will become, before any of it is
  real.

  An import is a tree of decisions, and import is possible iff every decision
  is resolved. `unresolved/1` is the single expression of that, so the import
  button, the queue's Ready badge and the tests cannot disagree.

  Nothing may be implicit: a field nobody proposed is a `:missing` decision
  the operator can see, and a field two sources disagree about is
  `:ambiguous` rather than silently first-wins.

  An embed, not staging tables: held in a jsonb column on `inbox_items`, so
  half-curated discoveries never touch the library tables. Embedded schemas
  buy changesets, validation and `inputs_for`, which is what makes the form
  ordinary nested LiveView.

  Rescans never touch a draft. Discovery updates `files`, `probe` and `tags`
  and stops; where the evidence genuinely moved, the affected decisions are
  marked stale rather than rewritten (`Ambry.Inbox.Draft.Seed.restale/2`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.Draft.Chapters
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.Work

  @primary_key false

  embedded_schema do
    # Asked first, because answering it yes settles everything below: only
    # the files of an existing audiobook are in question.
    embeds_one :replacement, Replacement, on_replace: :update

    embeds_one :work, Work, on_replace: :update
    embeds_one :recording, Recording, on_replace: :update
    embeds_one :destination, Destination, on_replace: :update

    # The humans this import will create or reuse, one record each. Credits
    # at both levels reference them by key.
    embeds_many :people, PersonDecision, on_replace: :delete

    # Bumped when discovery sees the underlying files change, so a draft can
    # say its evidence moved.
    field :evidence, :string
    field :stale, :boolean, default: false
  end

  @doc false
  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:evidence, :stale])
    |> cast_embed(:replacement)
    |> cast_embed(:work)
    |> cast_embed(:recording)
    |> cast_embed(:destination)
    |> cast_embed(:people)
  end

  @doc """
  Every decision still needing a human, in the order the form presents them.

  Returns a list of `%{section:, label:, state:}`. Empty means importable,
  which is the whole invariant.
  """
  def unresolved(nil), do: [%{section: :draft, label: "Not yet prepared", state: :missing}]

  def unresolved(%__MODULE__{} = draft) do
    stale(draft) ++ replacement(draft) ++ described(draft) ++ destination(draft)
  end

  # Replacing an audiobook collapses the rest: only where the new files go
  # is still a question.
  defp described(%__MODULE__{} = draft) do
    if Replacement.replacing?(draft.replacement),
      do: [],
      else: work(draft) ++ recording(draft) ++ people(draft)
  end

  # Absent on drafts that predate the decision, which are ordinary imports.
  defp replacement(%__MODULE__{replacement: nil}), do: []

  defp replacement(%__MODULE__{replacement: replacement}) do
    if Replacement.resolved?(replacement),
      do: [],
      else: [
        %{
          section: :replacement,
          label: "Whether this replaces an audiobook you already have",
          state: Replacement.state(replacement)
        }
      ]
  end

  # Asked once per human rather than once per credit: the invariant counts
  # decisions, and one human is one decision.
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

  # Absent only on drafts that predate the destination decision (an imported
  # item's draft is frozen history); a live draft always stages one.
  defp destination(%__MODULE__{destination: nil}), do: []

  defp destination(%__MODULE__{destination: destination}) do
    if Destination.resolved?(destination),
      do: [],
      else: [
        %{
          section: :destination,
          label: "Where the files go",
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

  A key with no decision behind it is skipped rather than crashing: a draft
  is operator input held in jsonb.
  """
  def people_for(draft, %Credit{} = credit),
    do: credit.person_keys |> Enum.map(&person(draft, &1)) |> Enum.reject(&is_nil/1)

  @doc """
  The humans this import will create, grouped by the credit that introduces
  them.

  One human is one record, so a person is listed once, under the first credit
  that names them, and the credits carry a reference. Grouping by credit keeps
  a composite pen name's people adjacent.

  Only people this import introduces: a credit pointing at an existing
  identity brings no humans, since that person carries curation an import may
  never overwrite. A person the operator matched to the library from their
  card stays listed, because nothing else proposes that link.

  Returns `[%{credit:, kind:, section:, index:, people: [...]}]`, dropping
  credits that introduce nobody new.
  """
  def people_groups(nil), do: []

  def people_groups(%__MODULE__{} = draft) do
    {groups, _seen} =
      Enum.reduce(credits(draft), {[], MapSet.new()}, fn {kind, section, index, credit},
                                                         {groups, seen} ->
        people = new_people(draft, credit, seen)

        if people == [] do
          {groups, seen}
        else
          group = %{credit: credit, kind: kind, section: section, index: index, people: people}
          {groups ++ [group], MapSet.union(seen, MapSet.new(people, & &1.key))}
        end
      end)

    groups
  end

  # A removed credit holds its person keys for a possible restore, but a
  # person only a tombstone references is nobody's decision.
  defp new_people(_draft, %Credit{removed: true}, _seen), do: []
  defp new_people(_draft, %Credit{mode: :link}, _seen), do: []

  defp new_people(draft, %Credit{} = credit, seen) do
    credit.person_keys
    |> Enum.map(&person(draft, &1))
    |> Enum.reject(&(is_nil(&1) or MapSet.member?(seen, &1.key)))
  end

  @doc """
  Which credits reference each person, so the form can say where they appear.

  Returns `%{key => [%{kind:, section:, index:, name:}]}`, derived every time
  rather than stored.
  """
  def appearances(nil), do: %{}

  def appearances(%__MODULE__{} = draft) do
    for {kind, section, index, credit} <- credits(draft),
        credit.mode == :create,
        not credit.removed,
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

  What `Seed` reconciles against: a person nobody credits has no reason to
  stay on the form, and a credit naming somebody new needs a decision.
  """
  def referenced_keys(%__MODULE__{} = draft) do
    for {_kind, _section, _index, credit} <- credits(draft),
        credit.mode == :create,
        # A removed credit holds its person_keys for its possible restore,
        # but a person only a tombstone references is nobody's decision.
        not credit.removed,
        key <- credit.person_keys,
        uniq: true,
        do: key
  end

  @doc """
  Whether a human has answered anything in this draft yet.

  Tells a draft that may be thrown away and rebuilt from fresh evidence from
  one that may only be re-derived around what the operator decided. A retry
  that finally reaches a provider needs the first, since its new record is
  not yet ticked.
  """
  def curated?(nil), do: false

  def curated?(%__MODULE__{} = draft) do
    # Answering the identity question and ticking records are curation too:
    # a draft whose only human input was either one must not be rebuilt
    # wholesale by the next background re-match.
    (draft.replacement && draft.replacement.curated) == true or
      Enum.any?(fields(draft), &(&1 && &1.curated)) or
      Enum.any?(credits(draft), fn {_kind, _section, _index, credit} -> credit.curated end) or
      Enum.any?((draft.work && draft.work.series) || [], & &1.curated) or
      Enum.any?(draft.people, & &1.curated) or
      (draft.work && (draft.work.curated or draft.work.evidence_curated)) == true or
      (draft.recording && draft.recording.evidence_curated) == true or
      (draft.recording && draft.recording.recording_group &&
         draft.recording.recording_group.curated) == true or
      (draft.recording && draft.recording.chapters && draft.recording.chapters.curated) == true
  end

  defp fields(%__MODULE__{work: work, recording: recording}) do
    work_fields = if work, do: [work.title, work.published], else: []

    recording_fields =
      if recording,
        do: [
          recording.title,
          recording.published,
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
  # stored, so it cannot drift.
  defp total(%__MODULE__{} = draft) do
    replacement_total(draft.replacement) + described_total(draft) +
      destination_total(draft.destination)
  end

  defp replacement_total(nil), do: 0
  defp replacement_total(%Replacement{}), do: 1

  # A replacement asks nothing about the audiobook itself, so counting those
  # decisions would leave the header reporting work that isn't there.
  defp described_total(%__MODULE__{} = draft) do
    if Replacement.replacing?(draft.replacement) do
      0
    else
      work_total(draft.work) + recording_total(draft.recording) + length(draft.people)
    end
  end

  defp destination_total(nil), do: 0
  defp destination_total(%Destination{}), do: 1

  defp work_total(nil), do: 1

  defp work_total(%Work{mode: :link} = work), do: 1 + live_count(work.series)

  defp work_total(%Work{} = work) do
    1 + 3 + live_count(work.authors) + live_count(work.series)
  end

  defp recording_total(nil), do: 1

  defp recording_total(%Recording{} = recording),
    do:
      1 + 5 + chapters_count(recording.chapters) + group_count(recording.recording_group) +
        live_count(recording.narrators)

  # nil until a probe has read the files — "not read yet" is not a decision
  defp chapters_count(nil), do: 0
  defp chapters_count(%Chapters{}), do: 1

  # at most one, and a tombstoned link is an answered question
  defp group_count(nil), do: 0
  defp group_count(%GroupLink{removed: true}), do: 0
  defp group_count(%GroupLink{}), do: 1

  # Tombstoned rows are answered questions; they neither count nor resolve.
  defp live_count(rows), do: Enum.count(rows, &(not &1.removed))
end
