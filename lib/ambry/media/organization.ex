defmodule Ambry.Media.Organization do
  @moduledoc """
  Keeping a managed recording's files where the naming template says.

  A library tree organized once at import drifts the moment anything is
  corrected: fix a misspelled title, reorder a book's authors, add the series
  you forgot, and the folder still says what it said when the file landed.
  Organizing brings the files back in line.

  ## What it will and won't touch

  Only `managed` recordings whose files sit inside a **registered library
  root**. That's two separate guards doing two separate jobs:

    * custody keeps it away from external files, which Ambry has promised
      never to write to;
    * the root check keeps it away from the legacy uploads library, which is
      `managed` but isn't template-organized and belongs to Phase 4.

  A rename stays inside the root the file already lives in, so it's always a
  move within one filesystem — never a copy, never a cross-device problem.

  ## Collisions refuse

  If the new path is already occupied, nothing moves. Two recordings
  rendering to one path is a curation problem the operator has to see, and
  quietly appending " (2)" would hide it forever.
  """

  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Library
  alias Ambry.Library.NamingTemplate
  alias Ambry.Media.Media
  alias Ambry.Repo
  alias Ambry.Settings
  alias Ambry.Utils

  require Logger

  @doc """
  Moves one recording's files to where the template says they belong.

  Returns `{:ok, :moved | :noop}` or `{:error, reason}`. Already being in
  the right place is a `:noop`, which is the common case every time this
  runs on a schedule.
  """
  def organize(%Media{} = media) do
    media =
      Repo.preload(media, [
        :media_tracks,
        :recording_group,
        book: [book_authors: :author, series_books: :series]
      ])

    with {:ok, root} <- root_for(media),
         {:ok, file} <- single_file(media),
         {:ok, destination} <- destination(media, root, file) do
      if destination == file, do: {:ok, :noop}, else: move(media, file, destination)
    else
      :noop -> {:ok, :noop}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Organizes every managed recording.

  The backstop for everything an edit-time trigger can't see — most obviously
  a change to the template itself, which invalidates every path at once.
  """
  def organize_all do
    Media
    |> where([m], m.custody == :managed)
    |> Repo.all()
    |> Enum.reduce(%{moved: 0, noop: 0, failed: 0}, fn media, counts ->
      case organize(media) do
        {:ok, :moved} ->
          Map.update!(counts, :moved, &(&1 + 1))

        {:ok, :noop} ->
          Map.update!(counts, :noop, &(&1 + 1))

        {:error, reason} ->
          Logger.warning(fn -> "Couldn't organize media #{media.id}: #{inspect(reason)}" end)
          Map.update!(counts, :failed, &(&1 + 1))
      end
    end)
    |> then(&{:ok, &1})
  end

  @doc """
  The managed recordings of one book, for after its metadata changed.
  """
  def book_media(book_id) do
    Media
    |> where([m], m.book_id == ^book_id and m.custody == :managed)
    |> Repo.all()
  end

  # The root the file already lives in. Not the location's *target* root —
  # this is about where the bytes are now, and a rename never moves a
  # recording between roots.
  defp root_for(%Media{custody: :managed, source_path: path}) when is_binary(path) do
    case Enum.find(Library.list_roots(), &inside?(path, &1.path)) do
      nil -> :noop
      root -> {:ok, root}
    end
  end

  defp root_for(%Media{}), do: :noop

  # Prefix-matching on a separator boundary, so `/data/library-old` is not
  # treated as living inside `/data/library`.
  defp inside?(path, root_path) do
    String.starts_with?(path, root_path <> "/")
  end

  # Direct-play v1 is single-file. A recording with several tracks would need
  # every one moved and re-pointed, which isn't reachable yet and shouldn't
  # be guessed at.
  defp single_file(%Media{media_tracks: [%{path: path}]}), do: {:ok, path}
  defp single_file(%Media{}), do: :noop

  defp destination(media, root, current_file) do
    values = Books.naming_values(media.book, media)

    with {:ok, folder} <- NamingTemplate.render(Settings.library_naming_template(), values),
         {:ok, filename} <- NamingTemplate.filename(values, current_file, filename_part(media)) do
      {:ok, Path.join([root.path, folder, filename])}
    end
  end

  # Without the part suffix, re-organizing one part of a set would rename it
  # onto its sibling's path (and refuse, or worse) — the same collision the
  # import-time suffix exists to prevent.
  defp filename_part(%Media{part_number: nil}), do: nil

  defp filename_part(%Media{part_number: number, recording_group: group}) do
    %{number: number, total: group && group.parts_total, word: group && group.part_word}
  end

  defp move(media, from, to) do
    cond do
      not File.regular?(from) ->
        # Reconciliation's job to notice and record, not this one's to guess
        # at. Moving a file that isn't there would only turn one problem into
        # two.
        {:error, {:source_missing, from}}

      File.exists?(to) ->
        {:error, {:destination_exists, to}}

      true ->
        do_move(media, from, to)
    end
  end

  defp do_move(media, from, to) do
    with :ok <- File.mkdir_p(Path.dirname(to)),
         :ok <- File.rename(from, to),
         {:ok, _media} <- repoint(media, from, to) do
      prune(from)
      {:ok, :moved}
    else
      {:error, reason} -> {:error, {:move_failed, reason}}
    end
  end

  defp repoint(media, from, to) do
    Repo.transact(fn ->
      with {:ok, _track} <- repoint_track(media, to) do
        media
        |> Ecto.Changeset.change(%{
          source_path: Path.dirname(to),
          source_files: replace_path(media.source_files, from, to)
        })
        |> Repo.update()
      end
    end)
  end

  defp repoint_track(%Media{media_tracks: [track]}, to) do
    track |> Ecto.Changeset.change(%{path: to}) |> Repo.update()
  end

  defp replace_path(source_files, from, to) when is_list(source_files) do
    Enum.map(source_files, fn path -> if path == from, do: to, else: path end)
  end

  defp replace_path(_source_files, _from, to), do: [to]

  # The folder the file just left, and any parent left empty by it. Passing
  # the old *file* path is what makes the pruning start at its folder rather
  # than at the folder's parent. Stops at any registered location — a root's
  # existence is configuration, not a consequence of holding a book.
  defp prune(from) do
    Utils.try_prune_empty_parents([from], Library.registered_paths())
  end
end
