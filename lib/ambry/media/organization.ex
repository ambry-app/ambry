defmodule Ambry.Media.Organization do
  @moduledoc """
  Keeping a recording's files where the naming template says.

  A library tree organized once at import drifts the moment anything is
  corrected: fix a misspelled title, reorder a book's authors, add the series
  you forgot, and the folder still says what it said when the file landed.
  Organizing brings the files back in line.

  ## What it will and won't touch

  Only files inside a **registered library root** — which keeps it away from
  the legacy uploads library, which isn't template-organized and belongs to
  Phase 4. Every recording in a root is organizable: what lives there is
  always Ambry's own name for the bytes (a hardlink, a symlink, a copy), and
  renaming a name never touches an original.

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
  alias Ambry.Library.Root
  alias Ambry.Media.Media
  alias Ambry.Media.MediaTrack
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
        :library_root,
        book: [book_authors: :author, series_books: :series]
      ])

    with {:ok, root} <- root_for(media),
         {:ok, files} <- current_files(media),
         {:ok, destinations} <- destinations(media, root, files) do
      if destinations == files,
        do: {:ok, :noop},
        else: move(media, root, Enum.zip(files, destinations))
    else
      :noop -> {:ok, :noop}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Organizes every recording.

  The backstop for everything an edit-time trigger can't see — most obviously
  a change to the template itself, which invalidates every path at once.
  """
  def organize_all do
    Media
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
  The recordings of one book, for after its metadata changed.
  """
  def book_media(book_id) do
    Media
    |> where([m], m.book_id == ^book_id)
    |> Repo.all()
  end

  # The FK, never an inferred prefix: the recording says which root its
  # files live in. A null FK is the legacy uploads tree, which isn't
  # template-organized and belongs to Phase 4.
  defp root_for(%Media{library_root: %Root{} = root}), do: {:ok, root}
  defp root_for(%Media{}), do: :noop

  # Where the recording's files are now, absolute and in play order. Track
  # order is the order the destination names are rendered in, so a
  # multi-file recording's file 003 stays file 003 across a rename.
  defp current_files(%Media{media_tracks: [_ | _] = tracks}) do
    {:ok, tracks |> Enum.sort_by(& &1.index) |> Enum.map(&track_disk_path!/1)}
  end

  defp current_files(%Media{}), do: :noop

  defp track_disk_path!(track) do
    {:ok, path} = MediaTrack.disk_path(track)
    path
  end

  defp destinations(media, root, current_files) do
    values = Books.naming_values(media.book, media)

    with {:ok, folder} <- NamingTemplate.render(Settings.library_naming_template(), values),
         {:ok, filenames} <-
           NamingTemplate.filenames(values, current_files, filename_recording(media)) do
      {:ok, Enum.map(filenames, &Path.join([root.path, folder, &1]))}
    end
  end

  # The same descriptor import placed the files under, so re-organizing a
  # recording lands it back on its own path rather than a sibling's.
  defp filename_recording(%Media{} = media) do
    %{part: filename_part(media), token: Media.filename_token(media)}
  end

  defp filename_part(%Media{part_number: nil}), do: nil

  defp filename_part(%Media{part_number: number, recording_group: group}) do
    %{number: number, total: group && group.parts_total, word: group && group.part_word}
  end

  # A file already sitting at its destination is skipped, not refused. Adding
  # one file to a forty-file recording renames only the forty-first: the rest
  # map to themselves, and treating "it's already there" as a collision would
  # fail every such re-organize.
  defp move(media, root, pairs) do
    pairs = Enum.reject(pairs, fn {from, to} -> from == to end)

    case Enum.find_value(pairs, &blocker/1) do
      nil -> do_move(media, root, pairs)
      reason -> {:error, reason}
    end
  end

  # Checked for every file before any of them moves. Half a renamed recording
  # is worse than an unrenamed one — the tracks would point at two different
  # folders — and the cheap checks are the ones that catch it.
  defp blocker({from, to}) do
    cond do
      # Reconciliation's job to notice and record, not this one's to guess
      # at. Moving a file that isn't there would only turn one problem into
      # two.
      not File.regular?(from) -> {:source_missing, from}
      File.exists?(to) -> {:destination_exists, to}
      true -> nil
    end
  end

  defp do_move(media, root, pairs) do
    with :ok <- rename_all(pairs),
         {:ok, _media} <- repoint(media, root, pairs) do
      pairs |> Enum.map(&elem(&1, 0)) |> prune()
      {:ok, :moved}
    else
      {:error, reason} -> {:error, {:move_failed, reason}}
    end
  end

  defp rename_all(pairs) do
    Enum.reduce_while(pairs, :ok, fn {from, to}, :ok ->
      with :ok <- File.mkdir_p(Path.dirname(to)),
           :ok <- File.rename(from, to) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # File operations happen in absolutes; what gets *written back* is the
  # stored form — relative to the root the rename stayed inside.
  defp repoint(media, root, pairs) do
    moved = Map.new(pairs)

    Repo.transact(fn ->
      with {:ok, _tracks} <- repoint_tracks(media, root, moved) do
        media
        |> Ecto.Changeset.change(%{
          source_path: relativize!(root, pairs |> List.last() |> elem(1) |> Path.dirname()),
          source_files: media |> replace_paths(moved) |> Enum.map(&relativize!(root, &1))
        })
        |> Repo.update()
      end
    end)
  end

  defp repoint_tracks(%Media{media_tracks: tracks}, root, moved) do
    tracks
    |> Enum.map(&{&1, Map.get(moved, track_disk_path!(&1))})
    |> Enum.filter(fn {_track, new_path} -> new_path end)
    |> Enum.reduce_while({:ok, []}, fn {track, new_path}, {:ok, acc} ->
      track
      |> Ecto.Changeset.change(%{path: relativize!(root, new_path), library_root_id: root.id})
      |> Repo.update()
      |> case do
        {:ok, track} -> {:cont, {:ok, [track | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp replace_paths(%Media{source_files: [_ | _]} = media, moved) do
    media |> Media.source_file_paths() |> Enum.map(&Map.get(moved, &1, &1))
  end

  # A recording old enough to have no `source_files` gets the one thing that
  # is certainly true afterwards: where its tracks are now.
  defp replace_paths(%Media{media_tracks: tracks}, moved) do
    tracks
    |> Enum.sort_by(& &1.index)
    |> Enum.map(&Map.get(moved, track_disk_path!(&1), track_disk_path!(&1)))
  end

  defp relativize!(root, absolute) do
    {:ok, relative} = Library.relativize(root, absolute)
    relative
  end

  # The folders the files just left, and any parent left empty by them.
  # Passing the old *file* paths is what makes the pruning start at their
  # folders rather than at the folders' parents. Stops at any registered
  # location — a root's existence is configuration, not a consequence of
  # holding a book.
  defp prune(from_paths) do
    Utils.try_prune_empty_parents(from_paths, Library.registered_paths())
  end
end
