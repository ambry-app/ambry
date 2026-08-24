defmodule Ambry.Library.Placement do
  @moduledoc """
  Bringing a file into a library root.

  Four policies, chosen per import. They are exhaustive: a file either shares
  its bytes with the original (hard or soft), duplicates them, or relocates
  them.

    * `:hardlink` — **same filesystem required**. One inode, two names, no
      extra bytes: the torrent keeps seeding from the downloads folder while
      the library serves the same bytes.
    * `:symlink` — the cross-filesystem answer to the same question.
    * `:copy` — duplicates. Honest and always possible.
    * `:move` — the library gets the file and the source folder is left clean.

  A symlink stores a path *string*, so the library entry dangles if the target
  moves and reconciliation reports the recording missing. Links are written
  **absolute**: a relative link survives only when link and target move as one
  tree, which is the case `:hardlink` already covers better.

  Hardlink refuses rather than falling back, because quietly copying is the
  storage doubling this exists to eliminate.

  Move deletes late: place-then-delete, deferred until the caller confirms the
  database work committed (`finalize/1`). The worst case is then a stray file
  in the library, which `undo/1` removes.
  """

  alias Ambry.Library

  @policies [:hardlink, :symlink, :copy, :move]

  # Recognizable in a directory listing, and outside every audio extension
  # the scanner knows, so a leftover can never be picked up as a track.
  @aside_suffix ".ambry-replaced"

  @enforce_keys [:source, :destination, :policy]
  defstruct [:source, :destination, :policy]

  defmodule Vacated do
    @moduledoc """
    A file moved out of the way of a replacement, and where it went.
    """

    @enforce_keys [:original, :aside]
    defstruct [:original, :aside]
  end

  @doc """
  The four doors, in the order they're offered.
  """
  def policies, do: @policies

  @doc """
  Places `source` at `destination` according to `policy`.

  Returns a struct describing what happened, which must be passed to
  `finalize/1` once the surrounding transaction commits, or to `undo/1` if it
  doesn't.
  """
  def place(source, destination, policy) when policy in @policies do
    with :ok <- readable(source),
         :ok <- vacant(destination),
         :ok <- File.mkdir_p(Path.dirname(destination)),
         :ok <- transfer(source, destination, policy) do
      {:ok, %__MODULE__{source: source, destination: destination, policy: policy}}
    end
  end

  @doc """
  Places every file of a multi-file recording, or none of them.

  Takes `{source, destination}` pairs in play order and returns the
  placements in the same order. The first failure undoes everything already
  placed: a book missing its last file is not a partial success.
  """
  def place_all(pairs, policy) do
    Enum.reduce_while(pairs, {:ok, []}, fn {source, destination}, {:ok, placed} ->
      case place(source, destination, policy) do
        {:ok, placement} ->
          {:cont, {:ok, [placement | placed]}}

        {:error, reason} ->
          undo(placed)
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, placed} -> {:ok, Enum.reverse(placed)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Completes a placement once the database work has committed.

  Only `:move` has anything left to do.
  """
  def finalize(placements) when is_list(placements) do
    placements
    |> Enum.map(&finalize/1)
    |> Enum.reject(&(&1 == :ok))
    |> case do
      [] -> :ok
      # The caller logs this and carries on either way.
      [error | _rest] -> error
    end
  end

  def finalize(%__MODULE__{policy: :move} = placement) do
    case File.rm(placement.source) do
      :ok -> :ok
      # Untidy, not broken: the import has already committed.
      {:error, reason} -> {:error, {:source_not_removed, reason}}
    end
  end

  def finalize(%__MODULE__{}), do: :ok

  @doc """
  Frees names the caller is about to place onto, reversibly.

  Placement never clobbers, and replacing an audiobook's files is the one
  case where the name in the way is the caller's own.

  Moved aside rather than deleted, and nothing is destroyed until the database
  says the replacement committed: `restore/1` puts it back if the placement
  fails, `discard/1` removes it once the records are in. A rename inside one
  directory is atomic, so this can sit inside the transaction.
  """
  def vacate(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, moved} ->
      case set_aside(path) do
        :vacant -> {:cont, {:ok, moved}}
        {:ok, vacated} -> {:cont, {:ok, [vacated | moved]}}
        {:error, reason} -> {:halt, restore_and_fail(moved, reason)}
      end
    end)
    |> case do
      {:ok, moved} -> {:ok, Enum.reverse(moved)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp set_aside(path) do
    case File.lstat(path) do
      {:error, _absent} ->
        :vacant

      {:ok, _occupied} ->
        aside = path <> @aside_suffix

        case File.rename(path, aside) do
          :ok -> {:ok, %Vacated{original: path, aside: aside}}
          {:error, reason} -> {:error, {:vacate_failed, path, reason}}
        end
    end
  end

  defp restore_and_fail(moved, reason) do
    restore(moved)
    {:error, reason}
  end

  @doc """
  Puts vacated files back, for when the placement or its records didn't land.
  """
  def restore(vacated) when is_list(vacated) do
    Enum.each(vacated, fn %Vacated{original: original, aside: aside} ->
      File.rename(aside, original)
    end)

    :ok
  end

  @doc """
  Removes vacated files, once the records that replaced them have committed.
  """
  def discard(vacated) when is_list(vacated) do
    Enum.each(vacated, fn %Vacated{aside: aside} -> File.rm(aside) end)
    :ok
  end

  @doc """
  Removes a placement, for when the surrounding transaction failed.

  Never touches the source — for every policy the source is still the only
  copy at this point.
  """
  def undo(placements) when is_list(placements) do
    Enum.each(placements, &undo/1)
    :ok
  end

  def undo(%__MODULE__{destination: destination}) do
    File.rm(destination)
    prune_empty_parents(Path.dirname(destination))
    :ok
  end

  def undo(_not_placed), do: :ok

  @doc """
  Whether a hardlink is possible between a source and a library root.

  Returns `{:error, reason}` rather than `false` when it can't be determined.
  """
  def hardlinkable?(source, root_path) do
    Library.same_filesystem?(source, root_path)
  end

  # Absolute target, deliberately: `source` is already absolute everywhere
  # placement is reached.
  defp transfer(source, destination, :symlink) do
    case File.ln_s(source, destination) do
      :ok -> :ok
      {:error, reason} -> {:error, {:symlink_failed, reason}}
    end
  end

  defp transfer(source, destination, :copy) do
    case File.cp(source, destination) do
      :ok -> :ok
      {:error, reason} -> {:error, {:copy_failed, reason}}
    end
  end

  # A move is a link-or-copy now and a delete later, so `:move` gets the
  # cheap same-filesystem path without ever being able to strand a file.
  defp transfer(source, destination, policy) when policy in [:hardlink, :move] do
    case File.ln(source, destination) do
      :ok ->
        :ok

      {:error, :exdev} when policy == :move ->
        transfer(source, destination, :copy)

      # Say so, rather than silently doubling the operator's storage.
      {:error, :exdev} ->
        {:error, {:cross_filesystem, source, destination}}

      {:error, reason} ->
        {:error, {:link_failed, reason}}
    end
  end

  defp readable(source) do
    if File.regular?(source), do: :ok, else: {:error, {:source_missing, source}}
  end

  # A collision means two recordings rendered to the same path, which the
  # operator has to see rather than get " (2)". `lstat` rather than
  # `exists?`: a dangling symlink occupies the name too.
  defp vacant(destination) do
    case File.lstat(destination) do
      {:ok, _occupied} -> {:error, {:destination_exists, destination}}
      {:error, _absent} -> :ok
    end
  end

  # An undone placement shouldn't leave its template folders standing empty.
  # Stops at the first non-empty directory, so it can never walk out of the
  # library root.
  defp prune_empty_parents(directory) do
    case File.ls(directory) do
      {:ok, []} ->
        case File.rmdir(directory) do
          :ok -> prune_empty_parents(Path.dirname(directory))
          {:error, _reason} -> :ok
        end

      _not_empty_or_unreadable ->
        :ok
    end
  end
end
