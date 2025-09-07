defmodule Ambry.Search.Index do
  @moduledoc """
  Context for updating search index records.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Media.Media
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Repo
  alias Ambry.Search.Record
  alias Ambry.Search.Reference

  # Insert

  def insert!(:book, book_id) do
    book = Book |> Repo.get!(book_id) |> Repo.preload([:series])
    series_ids = Enum.map(book.series, & &1.id)

    index!(:book, [book_id])
    index!(:series, series_ids)
  end

  def insert!(:media, media_id) do
    book_id =
      Repo.one!(
        from media in Media,
          where: media.id == ^media_id,
          select: media.book_id
      )

    index!(:book, [book_id])
  end

  def insert!(:person, person_id) do
    index!(:person, [person_id])
  end

  def insert!(:series, series_id) do
    series = Series |> Repo.get!(series_id) |> Repo.preload([:books])
    book_ids = Enum.map(series.books, & &1.id)

    index!(:series, [series_id])
    index!(:book, book_ids)
  end

  # Update

  def update!(:book, book_id) do
    reindex_dependents!(:book, book_id)
    index!(:book, [book_id])
  end

  def update!(:media, media_id) do
    reindex_dependents!(:media, media_id)
    insert!(:media, media_id)
  end

  def update!(:person, person_id) do
    reindex_dependents!(:person, person_id)
    index!(:person, [person_id])
  end

  def update!(:series, series_id) do
    reindex_dependents!(:series, series_id)
    index!(:series, [series_id])
  end

  # Delete

  def delete!(type, id) do
    reference = %Reference{type: type, id: id}

    {_count, nil} =
      Repo.delete_all(
        from record in Record,
          where: record.reference == type(^reference, Reference.Type)
      )

    reindex_dependents!(type, id)
  end

  # Nuke it

  # WARNING: drops and rebuilds the entire index, possibly really heavy
  def refresh_entire_index! do
    Repo.delete_all(Record)

    book_ids = Repo.all(from book in Book, select: book.id)
    index!(:book, book_ids)

    person_ids = Repo.all(from person in Person, select: person.id)
    index!(:person, person_ids)

    series_ids = Repo.all(from series in Series, select: series.id)
    index!(:series, series_ids)
  end

  # Private Impl

  defp index!(:book, book_ids) do
    books =
      Repo.all(
        from book in Book,
          where: book.id in ^book_ids,
          preload: [:series, authors: [:person], media: [narrators: [:person]]]
      )

    books
    |> Enum.map(&book_record/1)
    |> insert_records!()
  end

  defp index!(:media, media_ids) do
    books_ids =
      Repo.all(
        from media in Media,
          where: media.id in ^media_ids,
          select: media.book_id
      )

    index!(:book, books_ids)
  end

  defp index!(:person, person_ids) do
    people =
      Repo.all(
        from person in Person,
          where: person.id in ^person_ids,
          preload: [:authors, :narrators]
      )

    people
    |> Enum.map(&person_record/1)
    |> insert_records!()
  end

  defp index!(:series, series_ids) do
    series =
      Repo.all(
        from series in Series,
          where: series.id in ^series_ids,
          preload: [:series_books, authors: [:person]]
      )

    {series_to_insert, series_to_delete} =
      Enum.split_with(series, &(not Enum.empty?(&1.series_books)))

    series_to_insert
    |> Enum.map(&series_record/1)
    |> insert_records!()

    Enum.each(series_to_delete, fn series ->
      delete!(:series, series.id)
    end)

    :ok
  end

  defp book_record(book) do
    narrators = Enum.flat_map(book.media, & &1.narrators)

    {secondary_names, secondary_dependencies} = names(book.series ++ book.authors ++ narrators)

    {tertiary_names, tertiary_dependencies} = person_names(book.authors ++ narrators)

    media_dependencies = Enum.map(book.media, &Reference.new/1)

    dependencies =
      Enum.uniq(secondary_dependencies ++ tertiary_dependencies ++ media_dependencies)

    %{
      reference: Reference.new(book),
      dependencies: dependencies,
      primary: book.title,
      secondary: join(secondary_names),
      tertiary: join(tertiary_names)
    }
  end

  defp person_record(person) do
    person_name = person.name
    author_names = Enum.map(person.authors, & &1.name)
    narrator_names = Enum.map(person.narrators, & &1.name)

    {primary, secondary} =
      case join(author_names ++ narrator_names) do
        nil ->
          {person_name, nil}

        names ->
          {names,
           if(person_name not in author_names and person_name not in narrator_names,
             do: person_name
           )}
      end

    %{
      reference: Reference.new(person),
      dependencies: [],
      primary: primary,
      secondary: secondary
    }
  end

  defp series_record(series) do
    {secondary_names, secondary_dependencies} = names(series.authors)
    {tertiary_names, tertiary_dependencies} = person_names(series.authors)
    book_dependencies = Enum.map(series.books, &reference/1)
    dependencies = Enum.uniq(book_dependencies ++ secondary_dependencies ++ tertiary_dependencies)

    %{
      reference: Reference.new(series),
      dependencies: dependencies,
      primary: series.name,
      secondary: join(secondary_names),
      tertiary: join(tertiary_names)
    }
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

  defp insert_records!(records) do
    records
    |> Enum.chunk_every(100)
    |> Enum.each(fn records ->
      {_count, nil} =
        Repo.insert_all(Record, records,
          on_conflict: {:replace_all_except, [:reference]},
          conflict_target: [:reference]
        )
    end)

    :ok
  end

  defp reindex_dependents!(type, id) do
    reference = %Reference{type: type, id: id}

    records =
      Repo.all(
        from record in Record,
          where:
            fragment(
              "? = ANY(?)",
              type(^reference, Reference.Type),
              record.dependencies
            )
      )

    for {type, records} <- Enum.group_by(records, & &1.reference.type) do
      index!(type, Enum.map(records, & &1.reference.id))
    end

    :ok
  end
end
