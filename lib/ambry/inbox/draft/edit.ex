defmodule Ambry.Inbox.Draft.Edit do
  @moduledoc """
  The operations the import form performs on a staged import.

  Scalar *values* are ordinary form inputs — the form autosaves, so typing is
  handled by casting params. Everything here is the other half: the choices
  that aren't text, where the operator is picking between things rather than
  writing one (which candidate, which identity, who's behind a credit).

  Doing those as explicit operations rather than as more form params keeps
  each one a single named transition with the invariant intact afterwards,
  instead of a hidden-input trick whose meaning has to be reconstructed from
  the params on the way back in.
  """

  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.PersonRef
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Seed
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.SourceRef
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem

  @doc """
  Accepts one of a scalar's proposed candidates.
  """
  def choose_field(draft, section, name, key) do
    update_field(draft, section, name, &Field.choose(&1, key))
  end

  @doc """
  Settles a scalar as deliberately empty.
  """
  def waive_field(draft, section, name) do
    update_field(draft, section, name, &Field.waive/1)
  end

  @doc """
  Settles that this release is an edition of a Book already in the library.

  Nothing is created: the book's title, date and authors stay exactly as they
  are, and only the *additive* proposals — a series it isn't in yet — remain
  to decide. This is what stops a second recording of a work splitting the
  library in two, which is why it's the first question the form asks.
  """
  def link_book(draft, %InboxItem{} = item, book_id) do
    draft
    |> update_in([Access.key(:work)], &%{&1 | mode: :link, book_id: book_id, approved: true})
    |> reseed(item, :both)
  end

  @doc """
  Settles that this is a book the library doesn't have yet.

  Not a separate answer from "import this provider record" — importing a
  record IS creating a book. This is the answer to "is it one you already
  have", and it's no.
  """
  def new_book(draft, %InboxItem{} = item) do
    draft
    |> update_in([Access.key(:work)], &%{&1 | mode: :create, book_id: nil, approved: true})
    |> reseed(item, :both)
  end

  @doc """
  Adds or removes a provider record from those describing this import.

  Records are evidence, not identities: Hardcover and rreading-glasses both
  having a record of one book is the normal case, and each knows things the
  other doesn't. Ticking both is how the description comes from one and the
  cover from the other.
  """
  def toggle_source(draft, %InboxItem{} = item, level, record) do
    draft
    |> update_in([Access.key(level)], fn decision ->
      sources =
        if Enum.any?(decision.sources, &SourceRef.points_at?(&1, record)) do
          Enum.reject(decision.sources, &SourceRef.points_at?(&1, record))
        else
          decision.sources ++ [SourceRef.of(record)]
        end

      settle(%{decision | sources: sources}, level)
    end)
    |> follow_work(item, level, record)
    |> reseed(item, scope(level, record))
  end

  @doc """
  Settles the recording as one no catalogue lists, described by the file alone.

  A real answer rather than a failure: a delisted edition disappears from
  Audible's search *and* from direct ASIN lookup, so plenty of perfectly good
  rips are in no storefront at all.
  """
  def uncatalogued(draft, %InboxItem{} = item) do
    draft
    |> update_in([Access.key(:recording)], fn recording ->
      %{recording | sources: [], approved: true, doubt: :none, doubt_detail: nil}
    end)
    |> reseed(item, :recording)
  end

  # Ticking a record answers the question the level was asking, and a doubt
  # the operator has now overruled stops being a doubt.
  defp settle(decision, :recording),
    do: %{decision | approved: true, doubt: :none, doubt_detail: nil}

  defp settle(decision, :work), do: decision

  # A recording is a recording of exactly one work, so an edition record that
  # came out of a work's own list carries that work with it — ticking the
  # edition ticks the work rather than asking the same question twice.
  defp follow_work(draft, item, :recording, %{"of_work" => %{"source" => source, "id" => id}})
       when is_binary(source) do
    record = Enum.find(records(item, "work"), &(AutoMatch.ref(&1) == {source, to_string(id)}))

    cond do
      is_nil(record) -> draft
      Work.uses?(draft.work, record) -> draft
      true -> update_in(draft.work.sources, &(&1 ++ [SourceRef.of(record)]))
    end
  end

  defp follow_work(draft, _item, _level, _record), do: draft

  # Which levels a change has to re-derive. Ticking a recording record that
  # named its work has moved the work's ticked set too.
  defp scope(:work, _record), do: :work
  defp scope(:recording, %{"of_work" => %{"source" => source}}) when is_binary(source), do: :both
  defp scope(:recording, _record), do: :recording

  @doc """
  Re-derives every field from the currently ticked records.

  Called after new evidence arrives — a hydrated record, fresh search results
  — because a record that was a summary when it was ticked may now have a
  description and a cover to offer.
  """
  def resettle(draft, item), do: reseed(draft, item, :both)

  @doc """
  Whether a level currently counts this record.
  """
  def uses?(draft, :work, record), do: Work.uses?(draft.work, record)
  def uses?(draft, :recording, record), do: Recording.uses?(draft.recording, record)

  # Fields are derived from whichever records are ticked, so every change to
  # the ticked set re-derives them. Typed values and curated credits survive.
  #
  # Ticking a *recording* record leaves the work alone unless the record said
  # which work it belongs to — otherwise choosing an edition rebuilt the
  # authors the operator had just finished curating.
  defp reseed(draft, item, level) do
    work =
      if level in [:work, :both],
        do: Seed.reseed_work(draft.work, item),
        else: draft.work

    %{draft | work: work, recording: Seed.reseed_recording(draft.recording, item)}
  end

  defp records(item, level), do: Seed.records(item, level)

  @doc """
  Points a credit at an identity that already exists.
  """
  def link_credit(draft, section, index, identity_id) do
    update_credit(draft, section, index, fn credit ->
      %{credit | mode: :link, identity_id: identity_id, approved: true, curated: true}
    end)
  end

  @doc """
  Switches a credit to creating a new identity, backed by whoever is listed.

  Falls back to the 1:1 default when the list is empty, so the control is
  never in a state with nobody behind it.
  """
  def create_credit(draft, section, index) do
    update_credit(draft, section, index, fn credit ->
      people =
        if credit.people == [], do: Credit.new_person_default(credit.name), else: credit.people

      %{credit | mode: :create, identity_id: nil, people: people, curated: true}
    end)
  end

  @doc """
  Renames the identity a credit will create.

  A provider's spelling is a proposal like any other, and there was no way to
  overrule it — so "David Wong" could only ever be imported as a person called
  David Wong, when the human is Jason Pargin.

  The default person's name follows along while it is still tracking the
  credit, which is what makes that case two edits instead of a special mode:
  rename the credit, reveal the pen name, rename the person.
  """
  def rename_credit(draft, section, index, name) do
    update_credit(draft, section, index, fn credit ->
      people =
        Enum.map(credit.people, fn person ->
          if is_nil(person.person_id) and person.name == credit.name,
            do: %{person | name: name},
            else: person
        end)

      # Clearing the box un-confirms: a credit cannot stay settled with
      # nothing to create. Any other rename keeps the confirmation, so fixing
      # a typo doesn't cost a second click.
      %{
        credit
        | name: name,
          people: people,
          curated: true,
          approved: credit.approved and blank?(name) == false
      }
    end)
  end

  defp blank?(nil), do: true
  defp blank?(name) when is_binary(name), do: String.trim(name) == ""

  @doc """
  Renames the series a link will create.
  """
  def rename_series(draft, index, name) do
    update_series(
      draft,
      index,
      &%{&1 | name: name, curated: true, approved: &1.approved and not blank?(name)}
    )
  end

  @doc """
  Adds another human behind a credit.

  Two or more is a shared pen name — the whole of the composite-author case,
  expressed as a longer list rather than a different mode.
  """
  def add_person(draft, section, index) do
    update_credit(draft, section, index, fn credit ->
      %{credit | mode: :create, curated: true, people: credit.people ++ [%PersonRef{name: ""}]}
    end)
  end

  def remove_person(draft, section, index, person_index) do
    update_credit(draft, section, index, fn credit ->
      %{credit | curated: true, people: List.delete_at(credit.people, person_index)}
    end)
  end

  @doc """
  Names one of the people behind a credit, or points at an existing person.
  """
  def set_person(draft, section, index, person_index, attrs) do
    update_credit(draft, section, index, fn credit ->
      people =
        List.update_at(credit.people, person_index, fn person ->
          %{
            person
            | name: Map.get(attrs, :name, person.name),
              person_id: Map.get(attrs, :person_id, person.person_id)
          }
        end)

      %{credit | people: people, curated: true}
    end)
  end

  @doc """
  Marks a credit settled, or unsettles it for another look.
  """
  def approve_credit(draft, section, index, approved?) do
    update_credit(draft, section, index, &%{&1 | approved: approved?, curated: true})
  end

  @doc """
  Drops a proposed credit entirely — the source suggested somebody this
  recording isn't actually by.
  """
  def remove_credit(draft, section, index) do
    update_credits(draft, section, &List.delete_at(&1, index))
  end

  ## series

  def set_series_number(draft, index, number) do
    update_series(draft, index, &%{&1 | number: presence(number), curated: true})
  end

  def approve_series(draft, index, approved?) do
    update_series(draft, index, &%{&1 | approved: approved?, curated: true})
  end

  def link_series(draft, index, series_id) do
    update_series(draft, index, &%{&1 | mode: :link, series_id: series_id, curated: true})
  end

  def create_series(draft, index) do
    update_series(draft, index, &%{&1 | mode: :create, series_id: nil, curated: true})
  end

  def remove_series(draft, index) do
    update_in(draft.work.series, &List.delete_at(&1, index))
  end

  ## the identity decisions

  def approve_work(draft, approved?), do: update_in(draft.work.approved, fn _ -> approved? end)

  def approve_recording(draft, approved?),
    do: update_in(draft.recording.approved, fn _ -> approved? end)

  @doc """
  Takes the leading suggestion for everything still outstanding.

  Three things it deliberately will not do, because each would be the system
  writing a fact nobody actually has: invent a value nothing proposed, invent
  a series number, or pick a recording we already said we doubt. Those stay
  outstanding, which is the difference between a shortcut and a rubber stamp.
  """
  def approve_all(%Draft{} = draft) do
    draft
    |> update_in([Access.key(:work)], &approve_all_work/1)
    |> update_in([Access.key(:recording)], &approve_all_recording/1)
  end

  defp approve_all_work(work) do
    %{
      work
      | # With no candidates there is exactly one thing this can be — a new
        # book — so confirming it is precisely the nod this button is for.
        approved: true,
        title: settle_if_possible(work.title),
        published: settle_if_possible(work.published),
        published_format: settle_if_possible(work.published_format),
        authors: Enum.map(work.authors, &settle_credit/1),
        series: Enum.map(work.series, &settle_series/1)
    }
  end

  defp approve_all_recording(recording) do
    %{
      recording
      | # A doubted match is the one thing here that must stay a question. The
        # leading candidate for a narrator conflict is, by construction, the
        # wrong recording of the right book — precisely what nobody would
        # notice after the fact.
        approved: recording.approved or recording.doubt in [nil, :none, :nothing_found],
        title: settle_if_possible(recording.title),
        published: settle_if_possible(recording.published),
        publisher: settle_if_possible(recording.publisher),
        description: settle_if_possible(recording.description),
        cover: settle_if_possible(recording.cover),
        narrators: Enum.map(recording.narrators, &settle_credit/1)
    }
  end

  # Takes the first proposal where there is one; leaves a required field with
  # nothing behind it exactly as it was.
  defp settle_if_possible(%Field{approved: true} = field), do: field

  defp settle_if_possible(%Field{value: value} = field) when not is_nil(value),
    do: %{field | approved: true}

  defp settle_if_possible(%Field{candidates: [first | _rest]} = field),
    do: %{field | value: first.value, source: first.source, approved: true}

  defp settle_if_possible(%Field{required: false} = field), do: %{field | approved: true}
  defp settle_if_possible(field), do: field

  defp settle_credit(%Credit{} = credit) do
    cond do
      Credit.resolved?(credit) -> credit
      credit.mode == :link and credit.identity_id -> %{credit | approved: true}
      credit.people != [] -> %{credit | approved: true}
      true -> %{credit | people: Credit.new_person_default(credit.name), approved: true}
    end
  end

  # A number nobody supplied stays a question — this is the one thing the
  # approve-everything button must not paper over.
  defp settle_series(%SeriesLink{number: nil} = link), do: link
  defp settle_series(%SeriesLink{} = link), do: %{link | approved: true}

  ## plumbing

  defp update_field(draft, :work, name, fun),
    do: update_in(draft.work, &Map.update!(&1, name, fun))

  defp update_field(draft, :recording, name, fun),
    do: update_in(draft.recording, &Map.update!(&1, name, fun))

  defp update_credit(draft, section, index, fun),
    do: update_credits(draft, section, &List.update_at(&1, index, fun))

  defp update_credits(draft, :work, fun), do: update_in(draft.work.authors, fun)
  defp update_credits(draft, :recording, fun), do: update_in(draft.recording.narrators, fun)

  defp update_series(draft, index, fun),
    do: update_in(draft.work.series, &List.update_at(&1, index, fun))

  defp presence(nil), do: nil
  defp presence(string) when is_binary(string), do: with("" <- String.trim(string), do: nil)
  defp presence(other), do: other
end
