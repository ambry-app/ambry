defmodule Ambry.Library.Placement do
  @moduledoc """
  Bringing a file into a library root.

  Three policies, set per bring-in source:

    * `:hardlink` — **same filesystem required**. One inode, two names, no
      extra bytes. This is the point of the whole exercise: the torrent keeps
      seeding from the downloads folder while the library serves the same
      bytes.
    * `:copy` — duplicates. Honest and always possible.
    * `:move` — the library gets the file and the source folder is left clean.

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

  @enforce_keys [:source, :destination, :policy]
  defstruct [:source, :destination, :policy]

  @doc """
  Places `source` at `destination` according to `policy`.

  Returns a struct describing what happened, which must be passed to
  `finalize/1` once the surrounding transaction commits, or to `undo/1` if it
  doesn't.
  """
  def place(source, destination, policy) when policy in [:hardlink, :copy, :move] do
    with :ok <- readable(source),
         :ok <- vacant(destination),
         :ok <- File.mkdir_p(Path.dirname(destination)),
         :ok <- transfer(source, destination, policy) do
      {:ok, %__MODULE__{source: source, destination: destination, policy: policy}}
    end
  end

  @doc """
  Completes a placement once the database work has committed.

  Only `:move` has anything left to do.
  """
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

  # An adopted item was never placed, so there's nothing to finish.
  def finalize(nil), do: :ok

  @doc """
  Removes a placement, for when the surrounding transaction failed.

  Never touches the source — for every policy the source is still the only
  copy at this point.
  """
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
  # to paper over with " (2)".
  defp vacant(destination) do
    if File.exists?(destination), do: {:error, {:destination_exists, destination}}, else: :ok
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
