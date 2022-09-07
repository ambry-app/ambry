defmodule Ambry.Search.Index do
  @moduledoc """
  Context for updating search index records.
  """

  import Ecto.Query

  alias Ambry.{Reference, Repo}

  alias Ambry.Authors.Author
  alias Ambry.Media.Media
  alias Ambry.Narrators.Narrator
  alias Ambry.People.Person
  alias Ambry.Search.Record
  alias Ambry.Series.Series

  def index(type, id) when not is_list(id), do: index(type, [id])

  def index(:media, media_ids) do
    query =
      from media in Media,
        where: media.id in ^media_ids,
        preload: [narrators: [:person], book: [:series, authors: [:person]]]

    records =
      for media <- Repo.all(query) do
        primary_dependency = Reference.new(media.book)

        {secondary_names, secondary_dependencies} =
          names(media.book.series ++ media.book.authors ++ media.narrators)

        {tertiary_names, tertiary_dependencies} =
          person_names(media.book.authors ++ media.narrators)

        dependencies =
          Enum.uniq([primary_dependency | secondary_dependencies ++ tertiary_dependencies])

        %{
          reference: Reference.new(media),
          dependencies: dependencies,
          primary: media.book.title,
          secondary: join(secondary_names),
          tertiary: join(tertiary_names)
        }
      end

    insert_records(records)

    :ok
  end

  def index(:person, person_ids) do
    query =
      from person in Person,
        where: person.id in ^person_ids,
        preload: [:authors, :narrators]

    records =
      for person <- Repo.all(query) do
        person_name = person.name
        author_names = Enum.map(person.authors, & &1.name)
        narrator_names = Enum.map(person.narrators, & &1.name)

        %{
          reference: Reference.new(person),
          dependencies: [],
          primary: join(author_names ++ narrator_names),
          secondary:
            if(person_name not in author_names and person_name not in narrator_names,
              do: person_name
            )
        }
      end

    insert_records(records)

    :ok
  end

  def index(:series, series_ids) do
    query =
      from series in Series,
        where: series.id in ^series_ids,
        preload: [authors: [:person]]

    records =
      for series <- Repo.all(query) do
        {secondary_names, secondary_dependencies} = names(series.authors)
        {tertiary_names, tertiary_dependencies} = person_names(series.authors)
        dependencies = Enum.uniq(secondary_dependencies ++ tertiary_dependencies)

        %{
          reference: Reference.new(series),
          dependencies: dependencies,
          primary: series.name,
          secondary: join(secondary_names),
          tertiary: join(tertiary_names)
        }
      end

    insert_records(records)

    :ok
  end

  defp names(structs) do
    structs
    |> Enum.map(&{&1.name, reference(&1)})
    |> Enum.uniq()
    |> Enum.unzip()
  end

  defp person_names(authors_or_narrators) do
    authors_or_narrators
    |> Enum.reject(&(&1.name == &1.person.name))
    |> Enum.map(&{&1.person.name, reference(&1.person)})
    |> Enum.uniq()
    |> Enum.unzip()
  end

  defp reference(%Author{person: person}), do: Reference.new(person)
  defp reference(%Narrator{person: person}), do: Reference.new(person)
  defp reference(struct), do: Reference.new(struct)

  defp join([]), do: nil
  defp join(items), do: Enum.join(items, " ")

  defp insert_records(records) do
    Repo.insert_all(Record, records,
      on_conflict: {:replace_all_except, [:reference]},
      conflict_target: [:reference]
    )
  end

  def reindex_dependents(type, id) do
    reference = %Reference{type: type, id: id}

    records =
      Repo.all(
        from record in Record,
          where:
            fragment(
              "? = ANY(?)",
              type(^reference, Ambry.Ecto.Types.Reference),
              record.dependencies
            )
      )

    for {type, records} <- Enum.group_by(records, & &1.reference.type) do
      index(type, Enum.map(records, & &1.reference.id))
    end

    :ok
  end

  def delete(type, id) do
    reference = %Reference{type: type, id: id}

    Repo.delete_all(
      from record in Record,
        where: record.reference == type(^reference, Ambry.Ecto.Types.Reference)
    )

    :ok
  end

  # WARNING: drops and rebuilds the entire index, possibly really heavy
  def refresh_entire_index do
    Repo.delete_all(Record)

    media_ids = Repo.all(from media in Media, select: media.id)
    :ok = index(:media, media_ids)

    person_ids = Repo.all(from person in Person, select: person.id)
    :ok = index(:person, person_ids)

    series_ids = Repo.all(from series in Series, select: series.id)
    :ok = index(:series, series_ids)

    :ok
  end
end
