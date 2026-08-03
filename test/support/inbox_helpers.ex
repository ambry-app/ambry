defmodule Ambry.InboxHelpers do
  @moduledoc """
  Standing in for the operator at the import form.

  Approval now executes a resolved draft rather than deciding anything, so a
  test that wants to exercise approval has to get an item to the state the
  form would leave it in. `settle/2` does what an operator clicking through
  every outstanding decision does — no more, so a test can still assert that
  something specific was left unresolved.
  """

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.InboxItem

  @doc """
  Prepares a draft and approves every decision still outstanding.

  Options mirror the choices the form offers:

    * `:title`, `:published` — override a scalar as the operator typing it
    * `:series_number` — settle a series membership's number
  """
  def settle(%InboxItem{} = item, opts \\ []) do
    {:ok, item} = Inbox.prepare_draft(item)
    {:ok, item} = Inbox.update_draft(item, settled(item.draft, opts))

    item
  end

  defp settled(%Draft{} = draft, opts) do
    %{
      "work" => settled_work(draft.work, opts),
      "recording" => settled_recording(draft.recording, opts)
    }
  end

  defp settled_work(work, opts) do
    %{
      "mode" => to_string(work.mode),
      "book_id" => work.book_id,
      "approved" => true,
      "candidates" => work.candidates,
      "title" => settled_field(work.title, opts[:title]),
      "published" => settled_field(work.published, opts[:published]),
      "published_format" => settled_field(work.published_format, nil),
      "authors" => Enum.map(work.authors, &settled_credit/1),
      "series" => Enum.map(work.series, &settled_series(&1, opts[:series_number]))
    }
  end

  defp settled_recording(recording, opts) do
    %{
      "approved" => true,
      "candidates" => recording.candidates,
      "title" => settled_field(recording.title, nil),
      "published" => settled_field(recording.published, nil),
      "publisher" => settled_field(recording.publisher, nil),
      "description" => settled_field(recording.description, nil),
      "cover" => settled_field(recording.cover, opts[:cover]),
      "narrators" => Enum.map(recording.narrators, &settled_credit/1)
    }
  end

  # An override is the operator typing a value, so it records `manual`; with
  # no override, whatever the seeder proposed is simply accepted.
  defp settled_field(%Field{} = field, nil) do
    value = field.value || first_candidate(field)

    %{
      "value" => value,
      "source" => field.source || source_of(field, value),
      "approved" => true,
      "required" => field.required,
      "candidates" => Enum.map(field.candidates, &Map.from_struct/1)
    }
  end

  defp settled_field(%Field{} = field, override) do
    %{
      "value" => override,
      "source" => "manual",
      "approved" => true,
      "required" => field.required,
      "candidates" => Enum.map(field.candidates, &Map.from_struct/1)
    }
  end

  defp first_candidate(%Field{candidates: [first | _rest]}), do: first.value
  defp first_candidate(%Field{}), do: nil

  defp source_of(%Field{candidates: candidates}, value) do
    Enum.find_value(candidates, &(&1.value == value && &1.source))
  end

  defp settled_credit(%Credit{} = credit) do
    %{
      "name" => credit.name,
      "kind" => to_string(credit.kind),
      "mode" => to_string(credit.mode),
      "identity_id" => credit.identity_id,
      "source" => credit.source,
      "approved" => true,
      "people" => people_for(credit)
    }
  end

  # Linking needs nobody behind it — the identity already has whoever it has.
  defp people_for(%Credit{mode: :link}), do: []

  defp people_for(%Credit{people: []} = credit),
    do: [%{"name" => credit.name, "person_id" => nil}]

  defp people_for(%Credit{people: people}),
    do: Enum.map(people, &%{"name" => &1.name, "person_id" => &1.person_id})

  defp settled_series(%SeriesLink{} = link, number) do
    %{
      "name" => link.name,
      "mode" => to_string(link.mode),
      "series_id" => link.series_id,
      "number" => number || link.number || "1",
      "source" => link.source,
      "approved" => true
    }
  end
end
