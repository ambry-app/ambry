defmodule Ambry.Library.Mounts do
  @moduledoc """
  Which mount a path lives under, read live from `/proc/self/mountinfo`.

  "Same filesystem" and "can be hardlinked between" are different questions,
  and `link(2)` answers the second in terms of *mounts*:

    * Two mounts of one NFS export share a superblock, so one `st_dev`, and
      the kernel still refuses to link across them. A device comparison says
      "fine" and the refusal arrives after the destination folder exists.
    * The inverse on btrfs: one mount holds many subvolumes, each with its own
      anonymous `st_dev`, and links across subvolumes are refused too. There
      the mount table would wrongly say "same".

  So the hardlink question is device equality *refined by* mount identity,
  never one or the other (`Ambry.Library.same_filesystem?/2`).

  Read live rather than stored, because mount tables change with every
  remount and a stale answer is worse than none.

  **Known limit**: matching is by literal path prefix, so a registered path
  that is itself a symlink into another mount is attributed to the symlink's
  mount. Registered locations are mount-point-shaped in practice, and the
  worst case is placement's own loud refusal at link time.
  """

  @mountinfo "/proc/self/mountinfo"

  @doc """
  The mount table, as `%{id, mount_point}` entries in table order.

  `:unavailable` on systems without `#{@mountinfo}` — macOS has no
  equivalent, and there the device comparison is the best answer available.
  """
  def read(path \\ @mountinfo) do
    case File.read(path) do
      {:ok, content} -> {:ok, parse(content)}
      {:error, _reason} -> :unavailable
    end
  end

  @doc """
  Parses mountinfo content.

  Fields are space-separated with octal escapes inside the mount point
  (`\\040` for a space), so a plain split is safe and the escapes are undone
  afterwards.
  """
  def parse(content) do
    for line <- String.split(content, "\n", trim: true),
        [id, _parent, _dev, _root, mount_point | _rest] = String.split(line, " ") do
      %{id: String.to_integer(id), mount_point: unescape(mount_point)}
    end
  end

  @doc """
  The mount a path lives under: longest mount-point prefix, matched on a
  path-segment boundary so `/mnt/nas-a` never claims `/mnt/nas-abc`.

  Overmounts shadow, so among equal-length matches the later table entry wins.
  """
  def mount_of(path, mounts) do
    mounts
    |> Enum.with_index()
    |> Enum.filter(fn {mount, _index} -> covers?(mount.mount_point, path) end)
    |> Enum.max_by(fn {mount, index} -> {byte_size(mount.mount_point), index} end, fn -> nil end)
    |> case do
      # Every absolute path is under "/" at minimum; nil means the path (or
      # the table) wasn't absolute-shaped, and guessing helps nobody.
      nil -> {:error, :no_mount}
      {mount, _index} -> {:ok, mount}
    end
  end

  defp covers?("/", path), do: String.starts_with?(path, "/")

  defp covers?(mount_point, path),
    do: path == mount_point or String.starts_with?(path, mount_point <> "/")

  defp unescape(mount_point) do
    ~r/\\([0-7]{3})/
    |> Regex.replace(mount_point, fn _whole, octal ->
      <<String.to_integer(octal, 8)>>
    end)
  end
end
