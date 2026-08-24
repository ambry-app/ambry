defmodule Ambry.Inbox.Draft.Edit do
  @moduledoc """
  The operations the import form performs on a staged import.

  Scalar *values* are ordinary form inputs, since the form autosaves.
  Everything here is the other half: choices that are not text, where the
  operator picks between things rather than writing one.

  Explicit operations rather than more form params, so each is a named
  transition with the invariant intact afterwards.
  """

  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Chapters
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.Seed
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.SourceRef
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem
  alias Ambry.Media.Media.Chapter

  @doc """
  Settles that these files replace an audiobook the library already has.

  The answer that collapses the rest of the form: the audiobook keeps
  everything but its files. Nothing else on the draft is touched, so changing
  the answer back leaves every decision where the operator left it.
  """
  def replace_recording(draft, media_id) when is_integer(media_id) do
    update_in(
      draft,
      [Access.key(:replacement)],
      &Replacement.replace(with_replacement(&1), media_id)
    )
  end

  @doc """
  Settles that this is an audiobook the library doesn't have yet.
  """
  def new_recording(draft) do
    update_in(draft, [Access.key(:replacement)], &Replacement.new(with_replacement(&1)))
  end

  # A draft staged before the decision existed answers it now rather than
  # crashing: the operator is looking at the control.
  defp with_replacement(nil), do: %Replacement{}
  defp with_replacement(%Replacement{} = replacement), do: replacement

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

  Nothing is created: the book's title, date and authors stay as they are and
  only the additive proposals remain to decide. This is what stops a second
  recording of a work splitting the library in two.
  """
  def link_book(draft, %InboxItem{} = item, book_id) do
    draft
    |> update_in(
      [Access.key(:work)],
      &%{&1 | mode: :link, book_id: book_id, approved: true, curated: true}
    )
    |> reseed(item, :both)
  end

  @doc """
  Settles that this is a book the library doesn't have yet.

  Not a separate answer from "import this provider record", which is the same
  thing. This answers "is it one you already have", and it's no.
  """
  def new_book(draft, %InboxItem{} = item) do
    draft
    |> update_in(
      [Access.key(:work)],
      &%{&1 | mode: :create, book_id: nil, approved: true, curated: true}
    )
    |> reseed(item, :both)
  end

  @doc """
  Adds or removes a provider record from those describing this import.

  Records are evidence, not identities: two providers both holding a record
  of one book is the normal case, and ticking both is how the description
  comes from one and the cover from the other.
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

      settle(%{decision | sources: sources, evidence_curated: true}, level)
    end)
    |> follow_work(item, level, record)
    |> reseed(item, scope(level, record))
  end

  @doc """
  Adds or removes a person record from those describing this human.

  The same rule as `toggle_source/4`, one level down: the exact-name gate
  decides the initial ticks and the checkbox decides from there.

  Touching the evidence answers the level, as it does for a recording.
  """
  def toggle_person_source(draft, %InboxItem{} = item, key, record) do
    matched = get_in(item.matches, ["people", key])

    update_person(draft, key, fn person ->
      sources =
        if Enum.any?(person.sources, &SourceRef.points_at?(&1, record)) do
          Enum.reject(person.sources, &SourceRef.points_at?(&1, record))
        else
          person.sources ++ [SourceRef.of(record)]
        end

      Seed.rederive_person_evidence(
        %{
          person
          | sources: sources,
            curated: true,
            evidence_curated: true,
            approved: true,
            doubt: :none,
            doubt_detail: nil
        },
        matched
      )
    end)
  end

  @doc """
  Settles a person as one no database has a record of.

  The person level's "None of these". A human nobody has a record of is still
  importable, since a name is all a Person needs, so this settles the level
  rather than blocking anything.
  """
  def uncatalogued_person(draft, %InboxItem{} = item, key) do
    matched = get_in(item.matches, ["people", key])

    update_person(draft, key, fn person ->
      Seed.rederive_person_evidence(
        %{
          person
          | sources: [],
            curated: true,
            evidence_curated: true,
            approved: true,
            doubt: :none,
            doubt_detail: nil
        },
        matched
      )
    end)
  end

  @doc """
  Settles a level as one no catalogue lists, described by the file alone.

  A real answer rather than a failure: a delisted edition disappears from a
  storefront's search *and* its ASIN lookup.

  Both levels need it, or the only way out of a doubted level is ticking a
  record you do not believe. The recording's `approved` is set, because there
  it means "the evidence question is answered"; the work's means "is this a
  book you already have", which this must not answer.
  """
  def uncatalogued(draft, item, level \\ :recording)

  def uncatalogued(draft, %InboxItem{} = item, :recording) do
    draft
    |> update_in([Access.key(:recording)], fn recording ->
      %{
        recording
        | sources: [],
          approved: true,
          evidence_curated: true,
          doubt: :none,
          doubt_detail: nil
      }
    end)
    |> reseed(item, :recording)
  end

  def uncatalogued(draft, %InboxItem{} = item, :work) do
    draft
    |> update_in([Access.key(:work)], fn work ->
      %{work | sources: [], evidence_curated: true, doubt: :none, doubt_detail: nil}
    end)
    |> reseed(item, :work)
  end

  # Ticking a record answers the question the level was asking, and a doubt
  # the operator has now overruled stops being a doubt.
  defp settle(decision, :recording),
    do: %{decision | approved: true, doubt: :none, doubt_detail: nil}

  # Ticking a record has to clear the work's doubt, or the level stays
  # outstanding with no control on the page that settles it.
  #
  # `approved` is deliberately NOT touched here, unlike the recording's: at
  # this level it answers "is this a book you already have", which ticking a
  # provider record does not answer.
  defp settle(%Work{sources: []} = decision, :work), do: decision

  defp settle(decision, :work), do: %{decision | doubt: :none, doubt_detail: nil}

  # A recording is a recording of exactly one work, so an edition record from
  # a work's own list ticks that work too.
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

  Called after new evidence arrives, because a record that was a summary when
  it was ticked may now have a description and a cover to offer.
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
  # Ticking a recording record leaves the work alone unless the record said
  # which work it belongs to, or choosing an edition rebuilds the authors.
  defp reseed(draft, item, level) do
    work =
      if level in [:work, :both],
        do: Seed.reseed_work(draft.work, item),
        else: draft.work

    %{draft | work: work, recording: Seed.reseed_recording(draft.recording, item)}
    |> Seed.reseed_people(item)
    |> Seed.seed_group(item)
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
      keys =
        if credit.person_keys == [],
          do: Credit.new_person_default(credit.name),
          else: credit.person_keys

      %{credit | mode: :create, identity_id: nil, person_keys: keys, curated: true}
    end)
  end

  @doc """
  Renames the identity a credit will create.

  A provider's spelling is a proposal like any other. The default person's
  name follows along while it is still tracking the credit, which makes the
  pen-name case two edits rather than a special mode.
  """
  def rename_credit(draft, section, index, name) do
    was = Enum.at(credits_in(draft, section), index)

    if was && was.name == name,
      do: draft,
      else: do_rename_credit(draft, section, index, name, was)
  end

  # Renaming something to what it is already called is not an edit, and must
  # not spend the credit's `curated` flag saying it was.
  defp do_rename_credit(draft, section, index, name, was) do
    draft
    |> update_credit(section, index, fn credit ->
      # Clearing the box un-confirms: a credit cannot stay settled with
      # nothing to create. Any other rename keeps the confirmation.
      %{
        credit
        | name: name,
          curated: true,
          approved: credit.approved and not blank?(name),
          # An added row starts with nobody behind it and the first real
          # name mints its person. Keys are then stored, never re-derived.
          person_keys: mint_keys(credit, name)
      }
    end)
    |> follow_credit_name(was, name)
  end

  defp mint_keys(%Credit{mode: :create, person_keys: []}, name),
    do: Credit.new_person_default(name)

  defp mint_keys(credit, _name), do: credit.person_keys

  # A person still called what the credit called them follows the rename; one
  # whose name is their own is left alone. The `own_name` flag is checked as
  # well as the names, because the two agree for as long as it takes to type
  # the real one.
  defp follow_credit_name(draft, nil, _name), do: draft

  defp follow_credit_name(draft, %Credit{} = was, name) do
    Enum.reduce(was.person_keys, draft, fn key, draft ->
      update_person(draft, key, fn person ->
        if person.mode == :create and not person.own_name and
             tracking?(Field.value(person.name), was.name),
           do: %{person | name: Field.edit(person.name, name)},
           else: person
      end)
    end)
  end

  # A cleared box is nil in the person's field and "" in the credit, and a
  # bare == between them breaks tracking exactly at the clear-to-retype
  # moment.
  defp tracking?(person_name, credit_name), do: presence(person_name) == presence(credit_name)

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
  Puts the evidence's spelling back in a renamed credit.

  The way back the scalar fields have through their chips.
  """
  def reset_credit_name(draft, section, index) do
    case Enum.at(credits_in(draft, section), index) do
      %Credit{proposed_name: name} when is_binary(name) ->
        rename_credit(draft, section, index, name)

      _no_proposal ->
        draft
    end
  end

  @doc """
  Puts the evidence's spelling back in a renamed series.
  """
  def reset_series_name(draft, index) do
    case Enum.at(draft.work.series, index) do
      %SeriesLink{proposed_name: name} when is_binary(name) -> rename_series(draft, index, name)
      _no_proposal -> draft
    end
  end

  @doc """
  Says that the credited name is not the person's name.

  Separating them gives the person a name of their own, which puts a name box
  on their card, and un-approves it. Marking the credit curated stops a
  background re-match folding the two back together.
  """
  def separate_person_name(draft, section, index) do
    draft
    |> update_credit(section, index, &%{&1 | curated: true})
    |> then(fn draft ->
      case Enum.at(credit_at(draft, section, index).person_keys, 0) do
        nil ->
          draft

        key ->
          update_person(
            draft,
            key,
            &%{&1 | own_name: true, curated: true, name: unapprove(&1.name)}
          )
      end
    end)
  end

  @doc """
  Takes it back: the credited name is this human's name after all.

  Putting the credited name back is the whole of it: the box goes, and the
  name resumes following the credit.
  """
  def use_credited_name(draft, key) do
    name = crediting_name(draft, key)

    update_person(draft, key, fn person ->
      %{
        person
        | own_name: false,
          curated: true,
          name: if(name, do: Field.edit(person.name, name), else: person.name)
      }
    end)
  end

  # What the credit that introduces this human calls them. The credits are
  # the only thing that knows, since a key is minted once and then left alone.
  defp crediting_name(draft, key) do
    Enum.find_value(credits_in(draft, :work) ++ credits_in(draft, :recording), fn credit ->
      if not credit.removed and key in credit.person_keys, do: credit.name
    end)
  end

  defp credit_at(draft, :work, index), do: Enum.at(draft.work.authors, index)
  defp credit_at(draft, :recording, index), do: Enum.at(draft.recording.narrators, index)

  defp unapprove(%Field{} = field), do: %{field | approved: false}

  @doc """
  Adds another human behind a credit.

  Two or more is a shared pen name, expressed as a longer list rather than a
  different mode. The new person gets a key of their own straight away, since
  keying an unnamed human by their blank name would merge every unnamed row
  into one.
  """
  def add_person(draft, %InboxItem{} = item, section, index) do
    key = PersonDecision.split_key("person", keys(draft))

    draft
    |> update_credit(section, index, fn credit ->
      %{credit | mode: :create, curated: true, person_keys: credit.person_keys ++ [key]}
    end)
    |> Seed.reseed_people(item)
  end

  def remove_person(draft, %InboxItem{} = item, section, index, person_index) do
    draft
    |> update_credit(section, index, fn credit ->
      %{credit | curated: true, person_keys: List.delete_at(credit.person_keys, person_index)}
    end)
    |> Seed.reseed_people(item)
  end

  @doc """
  Points a credit's person at somebody already in the library.

  The whole reference moves, not a name on it: linking means the library's
  own Person, whose curation an import may never overwrite.
  """
  def link_person(draft, key, person_id) do
    update_person(draft, key, fn person ->
      %{person | mode: :link, person_id: person_id, approved: true, curated: true}
    end)
  end

  @doc """
  Switches a person back to one this import will create.
  """
  def create_person(draft, key) do
    update_person(draft, key, fn person ->
      %{person | mode: :create, person_id: nil, curated: true}
    end)
  end

  @doc """
  Renames the person this import will create.

  A provider's spelling is a proposal like any other, and a pen name would
  otherwise only ever be importable as a person of that name.
  """
  def rename_person(draft, key, name) do
    update_person(draft, key, fn person ->
      %{person | name: Field.edit(person.name, name), curated: true}
    end)
  end

  @doc """
  Gives a person a photo, or a bio, from the picker.

  Recorded with the provider that supplied it, so approval writes the created
  Person's provenance by construction. One human is one record, so there is
  nothing to mirror.
  """
  def choose_person_image(draft, key, candidate_key),
    do: update_person_field(draft, key, :image, &Field.choose(&1, candidate_key))

  def choose_person_bio(draft, key, candidate_key),
    do: update_person_field(draft, key, :description, &Field.choose(&1, candidate_key))

  @doc """
  Types a bio directly, as the operator's own words.

  A person's description is a description like any other, so it gets the same
  editable box a recording's has. Recorded as `manual`, which is what stops a
  later refresh overwriting the edit.
  """
  def edit_person_bio(draft, key, description),
    do: update_person_field(draft, key, :description, &Field.edit(&1, description))

  @doc """
  Settles a person's photo or bio as deliberately empty.
  """
  def waive_person_field(draft, key, name),
    do: update_person_field(draft, key, name, &Field.waive/1)

  @doc """
  Marks a person settled, or unsettles them for another look.
  """
  def approve_person(draft, key, approved?),
    do: update_person(draft, key, &%{&1 | approved: approved?, curated: true})

  @doc """
  Says that the identically-named person on another credit is somebody else.

  The default is that they are the same human, because an author reading
  their own book is the ordinary reason one name turns up on two credits.

  Splitting mints a **new key** rather than setting a flag: two rows both
  marked distinct would be told apart only by where they sat.
  """
  def split_person(draft, %InboxItem{} = item, section, index, person_index) do
    case at(draft, section, index, person_index) do
      nil ->
        draft

      old_key ->
        new_key = PersonDecision.split_key(old_key, keys(draft))

        draft
        |> update_credit(section, index, fn credit ->
          %{
            credit
            | curated: true,
              person_keys: List.replace_at(credit.person_keys, person_index, new_key)
          }
        end)
        |> Seed.reseed_people(item)
    end
  end

  defp at(draft, section, index, person_index) do
    credits = credits_in(draft, section)

    with %Credit{} = credit <- Enum.at(credits, index) do
      Enum.at(credit.person_keys, person_index)
    end
  end

  defp credits_in(draft, :work), do: (draft.work && draft.work.authors) || []
  defp credits_in(draft, :recording), do: (draft.recording && draft.recording.narrators) || []

  defp keys(%Draft{} = draft), do: Enum.map(draft.people, & &1.key)

  defp update_person(draft, key, fun) do
    update_in(draft.people, fn people ->
      Enum.map(people, fn person -> if person.key == key, do: fun.(person), else: person end)
    end)
  end

  defp update_person_field(draft, key, name, fun),
    do: update_person(draft, key, &Map.update!(&1, name, fun))

  @doc """
  Marks a credit settled, or unsettles it for another look.
  """
  def approve_credit(draft, section, index, approved?) do
    update_credit(draft, section, index, &%{&1 | approved: approved?, curated: true})
  end

  @doc """
  Drops a proposed credit — the source suggested somebody this recording
  isn't actually by.

  A tombstone, not a deletion: deleted outright, `Seed.keep_curated/2`
  re-appends the same proposal on the next reseed. The reseed also drops the
  people only this credit referenced, or an orphaned `PersonDecision` sits in
  `draft.people` unable to be seen or settled.

  A row the operator added themselves really is deleted, since no evidence
  proposed it.
  """
  def remove_credit(draft, %InboxItem{} = item, section, index) do
    case Enum.at(credits_in(draft, section), index) do
      %Credit{source: "manual"} ->
        draft
        |> update_credits(section, &List.delete_at(&1, index))
        |> Seed.reseed_people(item)

      _proposed ->
        draft
        |> update_credit(section, index, &%{&1 | removed: true, curated: true})
        |> Seed.reseed_people(item)
    end
  end

  @doc """
  Brings back a removed credit, exactly as it was when it was removed.
  """
  def restore_credit(draft, %InboxItem{} = item, section, index) do
    draft
    |> update_credit(section, index, &%{&1 | removed: false})
    |> Seed.reseed_people(item)
  end

  @doc """
  Adds a credit the sources didn't propose.

  The row starts blank and unconfirmed, and curated from birth so no reseed
  sweeps it away. Its person is minted by the first real name (see
  `rename_credit/4`).
  """
  def add_credit(draft, section) do
    credit = %Credit{
      kind: kind_of(section),
      name: "",
      source: "manual",
      mode: :create,
      curated: true
    }

    update_credits(draft, section, &(&1 ++ [credit]))
  end

  defp kind_of(:work), do: :author
  defp kind_of(:recording), do: :narrator

  ## ordering

  @doc """
  Moves a credit one slot up or down. List order is billing order, so an
  order the operator chose is an answer and both moved rows are marked
  curated: `Seed.keep_curated/2` rebuilds uncurated rows in derivation order
  and would undo the move.
  """
  def move_credit(draft, section, index, direction) do
    update_credits(draft, section, &swap(&1, index, direction))
  end

  @doc """
  Moves a series membership one slot up or down — same doctrine as
  `move_credit/4`; a book's series order is its own kind of billing.
  """
  def move_series(draft, index, direction) do
    update_in(draft.work.series, &swap(&1, index, direction))
  end

  defp swap(list, index, direction) do
    other = if direction == :up, do: index - 1, else: index + 1
    length = length(list)

    if index >= 0 and index < length and other >= 0 and other < length do
      a = list |> Enum.at(index) |> Map.put(:curated, true)
      b = list |> Enum.at(other) |> Map.put(:curated, true)

      list |> List.replace_at(index, b) |> List.replace_at(other, a)
    else
      list
    end
  end

  @doc """
  Adds a series membership the sources didn't propose.
  """
  def add_series(draft) do
    link = %SeriesLink{name: "", source: "manual", mode: :create, curated: true}
    update_in(draft.work.series, &(&1 ++ [link]))
  end

  @doc """
  Brings the draft's people into line with the credits, for callers outside
  this module: a person named for the first time needs their decision minted
  before approval can read it.
  """
  def sync_people(draft, %InboxItem{} = item), do: Seed.reseed_people(draft, item)

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

  # The same tombstone as `remove_credit/4`; a series references no people,
  # so there is nothing to reconcile. Operator-added rows really delete.
  def remove_series(draft, index) do
    case Enum.at(draft.work.series, index) do
      %SeriesLink{source: "manual"} ->
        update_in(draft.work.series, &List.delete_at(&1, index))

      _proposed ->
        update_series(draft, index, &%{&1 | removed: true, curated: true})
    end
  end

  def restore_series(draft, index) do
    update_series(draft, index, &%{&1 | removed: false})
  end

  ## chapters

  @doc """
  Replaces the chapter list with an applied titles merge.

  `marker_source` is nil for every UI path, since a titles merge changes no
  marker; the parameter is for callers staging a timeline that is not the
  probe's. Rows arrive already merged and are normalized here. Curated, so an
  applied merge survives reseeds.
  """
  def set_chapters(draft, rows, marker_source \\ nil) do
    rows = Enum.map(rows, &struct(Chapter, Map.take(&1, [:time, :title, :title_source])))

    update_in(draft.recording.chapters, fn decision ->
      decision = decision || %Chapters{}

      %{
        decision
        | chapters: rows,
          chapter_marker_source: marker_source || decision.chapter_marker_source,
          approved: true,
          curated: true
      }
    end)
  end

  ## the part set

  @doc """
  Declares this recording part of a set the sources didn't propose.
  """
  def add_group(draft) do
    link = %GroupLink{name: "", source: "manual", mode: :create, curated: true}
    put_in(draft.recording.recording_group, link)
  end

  def set_group_part(draft, number) do
    update_group(draft, &%{&1 | part_number: number, curated: true})
  end

  def set_group_total(draft, total) do
    update_group(draft, &%{&1 | parts_total: total, curated: true})
  end

  def approve_group(draft, approved?) do
    update_group(draft, &%{&1 | approved: approved?, curated: true})
  end

  # `facts` are the linked group's own name/total, carried for display only —
  # a :link never writes them back at import.
  def link_group(draft, group_id, facts \\ %{}) do
    update_group(
      draft,
      &%{
        &1
        | mode: :link,
          recording_group_id: group_id,
          name: facts[:name] || &1.name,
          parts_total: facts[:parts_total] || &1.parts_total,
          curated: true
      }
    )
  end

  def create_group(draft) do
    update_group(draft, &%{&1 | mode: :create, recording_group_id: nil, curated: true})
  end

  @doc """
  Renames the group a link will create.
  """
  def rename_group(draft, name) do
    update_group(
      draft,
      &%{&1 | name: name, curated: true, approved: &1.approved and not blank?(name)}
    )
  end

  @doc """
  Puts the evidence's spelling back in a renamed group.
  """
  def reset_group_name(draft) do
    case draft.recording.recording_group do
      %GroupLink{proposed_name: name} when is_binary(name) -> rename_group(draft, name)
      _no_proposal -> draft
    end
  end

  # The same tombstone-vs-delete split as `remove_series/2`: an
  # operator-added link really deletes, a proposal tombstones.
  def remove_group(draft) do
    case draft.recording.recording_group do
      nil -> draft
      %GroupLink{source: "manual"} -> put_in(draft.recording.recording_group, nil)
      _proposed -> update_group(draft, &%{&1 | removed: true, curated: true})
    end
  end

  def restore_group(draft) do
    update_group(draft, &%{&1 | removed: false})
  end

  ## the identity decisions

  @doc """
  Approves the machine's ticks exactly as they are — "yes, you were right."

  Ticking a record settles a level, but clicking an already-ticked one unticks
  it, so a level the seeder settled needs its own way to be confirmed. Changes
  no sources: it only records that a human looked.
  """
  def approve_work(draft, approved?), do: update_in(draft.work.approved, fn _ -> approved? end)

  def approve_recording(draft, approved?),
    do: update_in(draft.recording.approved, fn _ -> approved? end)

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

  defp update_group(draft, fun) do
    case draft.recording.recording_group do
      nil -> draft
      %GroupLink{} = link -> put_in(draft.recording.recording_group, fun.(link))
    end
  end

  defp presence(nil), do: nil
  defp presence(string) when is_binary(string), do: with("" <- String.trim(string), do: nil)
  defp presence(other), do: other
end
