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
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem

  @doc """
  Accepts one of a scalar's proposed candidates.
  """
  def choose_field(draft, section, name, source) do
    update_field(draft, section, name, &Field.choose(&1, source))
  end

  @doc """
  Settles a scalar as deliberately empty.
  """
  def waive_field(draft, section, name) do
    update_field(draft, section, name, &Field.waive/1)
  end

  @doc """
  Settles which Book this is, and fills the work's fields from that answer.

  Choosing used to only flip `mode`, which is why every provider row rendered
  as chosen and clicking one appeared to do nothing: the fields had been
  seeded from the top hit at build time and no later choice could move them.
  A release is a recording of exactly one work, so picking a different
  candidate has to change what the book will say.
  """
  def choose_work(draft, %InboxItem{} = item, source, id) do
    case find_candidate(draft.work.candidates, source, id) do
      nil ->
        draft

      candidate ->
        # Clicking the row that's already chosen is a confirmation, not a
        # change — re-seeding there would silently discard every credit and
        # series the operator has settled since.
        if Work.selected?(draft.work, candidate) do
          update_in(draft.work, &%{&1 | approved: true})
        else
          update_in(draft.work, &Seed.reseed_work(&1, candidate, hints(item), tags(item)))
        end
    end
  end

  @doc """
  Settles the work as a book nothing matched, described by the file alone.
  """
  def choose_new_work(draft, %InboxItem{} = item) do
    update_in(draft.work, &Seed.reseed_new_work(&1, hints(item), tags(item)))
  end

  @doc """
  Settles which catalogued recording this release is.

  Because a recording is a recording of exactly one work, a candidate that
  came out of a work's own edition list answers the book question too — so
  choosing it settles the work rather than asking again.
  """
  def choose_recording(draft, %InboxItem{} = item, source, id) do
    case find_candidate(draft.recording.candidates, source, id) do
      nil ->
        draft

      candidate ->
        draft
        |> update_in([Access.key(:recording)], fn recording ->
          if Recording.selected?(recording, candidate),
            do: %{recording | approved: true, doubt: :none, doubt_detail: nil},
            else: Seed.reseed_recording(recording, candidate, work_chain(draft), tags(item), item)
        end)
        |> follow_work(item, candidate)
    end
  end

  @doc """
  Settles the recording as one no catalogue lists.

  A real answer, not a failure: a delisted edition disappears from Audible's
  search *and* from direct ASIN lookup, so plenty of perfectly good rips are
  in no storefront at all.
  """
  def choose_uncatalogued(draft, %InboxItem{} = item) do
    update_in(draft.recording, &Seed.reseed_uncatalogued(&1, work_chain(draft), tags(item), item))
  end

  # The chosen book's sources, which get a say in the recording's descriptive
  # fields.
  defp work_chain(draft), do: draft.work |> Seed.selected_candidate() |> Seed.chain()

  defp follow_work(draft, item, %{"of_work" => %{"source" => source, "id" => id}})
       when is_binary(source) do
    if Work.selected?(draft.work, %{"source" => source, "id" => id}),
      do: draft,
      else: choose_work(draft, item, source, id)
  end

  defp follow_work(draft, _item, _candidate), do: draft

  defp find_candidate(candidates, source, id) do
    Enum.find(candidates, fn candidate ->
      candidate["source"] == source and to_string(candidate["id"]) == to_string(id)
    end)
  end

  defp hints(%InboxItem{} = item), do: AutoMatch.hints(item)
  defp tags(%InboxItem{tags: tags}), do: tags || %{}

  @doc """
  Points a credit at an identity that already exists.
  """
  def link_credit(draft, section, index, identity_id) do
    update_credit(draft, section, index, fn credit ->
      %{credit | mode: :link, identity_id: identity_id, approved: true}
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

      %{credit | mode: :create, identity_id: nil, people: people}
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
      %{credit | name: name, people: people, approved: credit.approved and blank?(name) == false}
    end)
  end

  defp blank?(nil), do: true
  defp blank?(name) when is_binary(name), do: String.trim(name) == ""

  @doc """
  Renames the series a link will create.
  """
  def rename_series(draft, index, name) do
    update_series(draft, index, &%{&1 | name: name, approved: &1.approved and not blank?(name)})
  end

  @doc """
  Adds another human behind a credit.

  Two or more is a shared pen name — the whole of the composite-author case,
  expressed as a longer list rather than a different mode.
  """
  def add_person(draft, section, index) do
    update_credit(draft, section, index, fn credit ->
      %{credit | mode: :create, people: credit.people ++ [%PersonRef{name: ""}]}
    end)
  end

  def remove_person(draft, section, index, person_index) do
    update_credit(draft, section, index, fn credit ->
      %{credit | people: List.delete_at(credit.people, person_index)}
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

      %{credit | people: people}
    end)
  end

  @doc """
  Marks a credit settled, or unsettles it for another look.
  """
  def approve_credit(draft, section, index, approved?) do
    update_credit(draft, section, index, &%{&1 | approved: approved?})
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
    update_series(draft, index, &%{&1 | number: presence(number)})
  end

  def approve_series(draft, index, approved?) do
    update_series(draft, index, &%{&1 | approved: approved?})
  end

  def link_series(draft, index, series_id) do
    update_series(draft, index, &%{&1 | mode: :link, series_id: series_id})
  end

  def create_series(draft, index) do
    update_series(draft, index, &%{&1 | mode: :create, series_id: nil})
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
