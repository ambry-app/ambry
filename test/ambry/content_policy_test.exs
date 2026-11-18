defmodule Ambry.ContentPolicyTest do
  @moduledoc """
  The vocabulary half of the content policy in `AGENTS.md`, enforced rather
  than remembered.
  """

  use ExUnit.Case, async: true

  @banned ~r/torrent|usenet|\bnzb\b|magnet:\?/i

  test "no file in the repository names an acquisition tool or network" do
    {files, 0} = System.cmd("git", ["ls-files", "-z"])

    offenders =
      files
      |> String.split(<<0>>, trim: true)
      |> Enum.reject(&(&1 in ["test/ambry/content_policy_test.exs", "mix.lock"]))
      |> Enum.flat_map(&offences/1)

    assert offenders == [],
           """
           See "Content policy" in AGENTS.md.

           #{Enum.map_join(offenders, "\n", fn {file, line} -> "  #{file}: #{line}" end)}
           """
  end

  defp offences(file) do
    with {:ok, text} <- File.read(file),
         true <- String.valid?(text) do
      text
      |> String.split("\n")
      |> Enum.filter(&Regex.match?(@banned, &1))
      |> Enum.map(&{file, String.trim(&1)})
    else
      _ -> []
    end
  end
end
