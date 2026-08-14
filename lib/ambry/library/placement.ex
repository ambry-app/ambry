defmodule Ambry.Library.Placement do
  @moduledoc """
  Bringing a file into a library root.

  Four policies, chosen per import. They are exhaustive: a file either
  shares its bytes with the original (hard or soft), duplicates them, or
  relocates them — there is no fifth door.

    * `:hardlink` — **same filesystem required**. One inode, two names, no
      extra bytes. This is the point of the whole exercise: the torrent keeps
      seeding from the downloads folder while the library serves the same
      bytes.
    * `:symlink` — the cross-filesystem answer to the same question, with
      real burdens the operator accepts by choosing it (below).
    * `:copy` — duplicates. Honest and always possible.
    * `:move` — the library gets the file and the source folder is left clean.

  ## What choosing symlink takes on

  A symlink stores a path *string*, not a reference to the bytes, so the
  library entry dangles if the target is moved or deleted — reconciliation
  reports the recording missing, which is the honest answer, and recreating
  the link is the only repair. Links are written **absolute**: a relative
  link survives only when link and target move as one tree, and that is
  exactly the shared-filesystem case where `:hardlink` is available and
  strictly better. Two consequences worth telling the operator at the point
  of choosing: the link breaks if either mount path changes, and a link
  written from inside a container encodes the *container's* view of the
  path — the same tree read from the NAS host sees dangling links. Not a
  data-loss risk; the bytes are untouched. But the library tree stops being
  self-describing outside Ambry.

  Unlike `:hardlink`, symlink has no precondition to fail — that is the
  point of having it — so it gets no feasibility blocker.

  ## Why hardlink refuses instead of falling back

  A hardlink cannot cross a filesystem, and in this deployment the downloads
  folder and the library live on two different NAS boxes. The tempting
  behaviour — quietly copy when a link isn't possible — is precisely the
  storage doubling this whole phase exists to eliminate, and it fails
  *silently*: the operator asked for 1x storage and gets 2x with no
  indication. So `:hardlink` across filesystems is an error, and the operator
  either moves the root or picks `:copy` deliberately.

  ## Why move deletes late

  `:move` is implemented as place-then-delete, with the delete deferred until
  the caller confirms the database work committed (`finalize/1`). A file moved
  before a failed commit is a file with no record pointing at it — the source
  gone, the library row absent. Linking (or copying) first means the worst
  case is a stray file in the library, which `undo/1` removes and the audit
  tooling would spot anyway.
  """

  alias Ambry.Library

  @policies [:hardlink, :symlink, :copy, :move]

  @enforce_keys [:source, :destination, :policy]
  defstruct [:source, :destination, :policy]

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
  placements in the same order. A recording is one thing: thirty-nine linked
  files and a fortieth that hit a full disk is not a partial success, it's a
  book that plays up to chapter 39 and then stops. So the first failure
  undoes everything already placed and reports why — the same all-or-nothing
  the surrounding transaction gives the database records.
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
      # One source that wouldn't go away is reported, not accumulated: the
      # caller logs this and carries on either way, and the first reason is
      # the one worth reading.
      [error | _rest] -> error
    end
  end

  def finalize(%__MODULE__{policy: :move} = placement) do
    case File.rm(placement.source) do
      :ok -> :ok
      # The library copy exists and is recorded; a source we couldn't remove
      # is untidy, not broken, and must not fail an import that has already
      # committed.
      {:error, reason} -> {:error, {:source_not_removed, reason}}
    end
  end

  def finalize(%__MODULE__{}), do: :ok

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

  Returns `{:error, reason}` rather than `false` when it can't be determined:
  "I couldn't tell" must never be actioned as "different filesystem, copy
  instead".
  """
  def hardlinkable?(source, root_path) do
    Library.same_filesystem?(source, root_path)
  end

  # Absolute target, deliberately — see the moduledoc. `source` is already
  # absolute everywhere placement is reached (sources and roots both validate
  # it), so this writes the link content as given rather than re-deriving it.
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

      # The whole reason this module exists: say so, don't silently double
      # the operator's storage.
      {:error, :exdev} ->
        {:error, {:cross_filesystem, source, destination}}

      {:error, reason} ->
        {:error, {:link_failed, reason}}
    end
  end

  defp readable(source) do
    if File.regular?(source), do: :ok, else: {:error, {:source_missing, source}}
  end

  # Never clobber. A collision means two recordings rendered to the same
  # path, which is a curation problem the operator has to see, not something
  # to paper over with " (2)". `lstat` rather than `exists?`: a dangling
  # symlink occupies the name too, and `exists?` follows links.
  defp vacant(destination) do
    case File.lstat(destination) do
      {:ok, _occupied} -> {:error, {:destination_exists, destination}}
      {:error, _absent} -> :ok
    end
  end

  # An undone placement shouldn't leave "Brandon Sanderson/The Stormlight
  # Archive/" standing empty. Stops at the first non-empty directory, so it
  # can never walk up out of the library root.
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
