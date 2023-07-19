defmodule Ambry.Uploads do
  @moduledoc false

  alias Ambry.Metadata.GoodReads
  alias Ambry.Repo
  alias Ambry.Uploads.Upload

  @doc """
  Changeset for an upload
  """
  def change_upload(%Upload{} = upload, attrs \\ %{}) do
    Upload.changeset(upload, attrs)
  end

  @doc """
  Create a new upload
  """
  def create_upload(attrs) do
    %Upload{}
    |> Upload.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an upload
  """
  def update_upload(%Upload{} = upload, attrs) do
    upload
    |> Upload.changeset(attrs)
    |> Repo.update()
  end

  # TODO: docs
  def get_upload!(id) do
    Upload
    |> Repo.get!(id)
    # FIXME:
    |> Repo.preload([:upload_narrators, book: [book_authors: [:author], series_books: [:series]]])
  end

  # TODO: docs
  def add_metadata(%Upload{} = upload, metadata_module) do
    files_params =
      Enum.map(upload.source_files, fn file ->
        case metadata_module.get_metadata(file) do
          {:ok, metadata} ->
            %{
              id: file.id,
              metadata: Map.put(file.metadata, inspect(metadata_module), %{"ok" => metadata})
            }

          {:error, reason} ->
            %{
              id: file.id,
              metadata: Map.put(file.metadata, inspect(metadata_module), %{"error" => inspect(reason)})
            }
        end
      end)

    upload
    |> Upload.changeset(%{source_files: files_params})
    |> Repo.update()
  end

  def gr(upload) do
    {:ok, search} = GoodReads.search_books(upload.title)
    best_match = List.first(search.results)
    {:ok, editions} = GoodReads.editions(best_match.id)
    most_popular_edition = List.first(editions.editions)

    most_popular_audio_edition =
      Enum.find(editions.editions, fn edition ->
        edition.format |> String.downcase() |> String.contains?("audio")
      end)

    {:ok, most_popular_edition_details} = GoodReads.edition_details(most_popular_edition.id)

    {:ok, most_popular_audio_edition_details} = GoodReads.edition_details(most_popular_audio_edition.id)

    {
      most_popular_edition_details,
      most_popular_audio_edition_details
    }
  end

  # def infer_basic_details(%Upload{} = _upload) do

  # end

  # def infer_basic_details(%File{} = file) do
  #   cond do
  #     Map.has_key?(file.metadata, "Ambry.Metadata.FFProbe") ->

  #   end

  #   {title, author}
  # end

  # defp infer_basic_details_from_file(%File{} = file) do
  #   title_candidate = file.filename |> Path.rootname() |> String.downcase()
  # end

  # @non_ascii ~r/[^[:alnum:]\s]+/
  # @spaces ~r/\s+/
  # @part ~r/(part|track)\s?[0-9]+/
  # @of ~r/[0-9]+\s?of\s?[0-9]+/
  # @dash ~r/[0-9]+-[0-9]+/
  # @book ~r/book\s?[0-9]+/
  # @trailing_numbers ~r/[0-9]+$/
  # def common(filenames) do
  #   Enum.map(filenames, fn filename ->
  #     filename
  #     |> Path.rootname()
  #     |> String.downcase()
  #     |> String.replace(@dash, "")
  #     |> String.replace(@non_ascii, "")
  #     |> String.replace(@spaces, " ")
  #     |> String.replace(@book, "")
  #     |> String.replace(@part, "")
  #     |> String.replace(@of, "")
  #     |> String.replace(@trailing_numbers, "")
  #     |> String.trim()
  #   end)
  # end
end
