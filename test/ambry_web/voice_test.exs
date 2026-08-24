defmodule AmbryWeb.VoiceTest do
  @moduledoc """
  §8's dash rule, enforced rather than remembered.

  "No em or en dashes in rendered text" has been the rule since the
  vocabulary pass, and it was still broken in nine places across five files
  when it was next looked at: a provider's setup help, a token expiry
  warning, a match explanation, a watch's expected date. Every one was
  written by somebody who had read the rule and was writing prose, which is
  the failure a prose rule cannot prevent.

  So it is a test. It reads the source rather than rendering pages, because
  the strings that broke it live in contexts an admin test never reaches, and
  a rule that only covers the pages somebody thought to test is the rule that
  let these through.

  What it deliberately does not read, because none of it is rendered text:

    * comments, `@moduledoc`, `@doc`, `@desc` and the `doc:` on an `attr` or
      `slot` — written for whoever is reading the code (or the schema), this
      document included;
    * sigils other than `~H` — a release name is *full* of dashes, and the
      patterns that parse one have to say so;
    * HEEx comments inside a `~H` template, which are comments wherever they
      live.

  The one dash §8 leaves standing is the empty-value placeholder in a cell,
  and it is allowed here as *a string that is nothing but the dash*. That is
  narrow enough to be exactly the placeholder and nothing else, and it has
  one home anyway: `AmbryWeb.Admin.Components`' `empty_value/0`.
  """

  use ExUnit.Case, async: true

  @dashes ~r/[\x{2013}\x{2014}]/u

  # §8's one survivor: a cell with no value in it. Narrow on purpose, so it
  # covers the placeholder and never a dash inside a sentence.
  @placeholders ["\u2014", "\u2013"]

  @heex_comment ~r/<%!--.*?--%>/s

  test "no em or en dashes in rendered text" do
    offenders = Enum.flat_map(sources(), &offences/1)

    assert offenders == [],
           """
           §8: no em or en dashes in rendered text. Rewrite the sentence instead:
           two short sentences, a semicolon, parentheses, or a comma.

           #{Enum.map_join(offenders, "\n", fn {file, text} -> "  #{file}\n      #{text}" end)}
           """
  end

  defp sources do
    Path.wildcard("lib/**/*.ex") ++ Path.wildcard("lib/**/*.heex")
  end

  defp offences(file) do
    file
    |> File.read!()
    |> rendered_text(file)
    |> Enum.flat_map(&String.split(&1, "\n"))
    |> Enum.filter(&(&1 =~ @dashes))
    |> Enum.reject(&(String.trim(&1) in @placeholders))
    |> Enum.map(&{file, String.trim(&1)})
  end

  # A `.heex` file is a template, not a module: its literal text is the
  # rendered text, so it is read as text with its comments cut out.
  defp rendered_text(source, file) do
    if String.ends_with?(file, ".heex") do
      [strip_comments(source)]
    else
      source |> Code.string_to_quoted!() |> strings()
    end
  end

  defp strip_comments(text), do: Regex.replace(@heex_comment, text, "")

  # An AST walk, so comments and doc attributes are excluded for free rather
  # than by a regex that has to recognize them. Returning something else in
  # place of a node prunes it, which is how the exemptions above are skipped
  # without being read.
  defp strings(ast) do
    {_pruned, found} =
      Macro.prewalk(ast, [], fn
        {:@, _meta, [{doc, _, _}]}, acc when doc in [:moduledoc, :doc, :typedoc, :desc] ->
          {:pruned, acc}

        {:doc, _value}, acc ->
          {:pruned, acc}

        {:sigil_H, meta, args}, acc ->
          {{:sigil_H, meta, Macro.prewalk(args, &prune_heex_comments/1)}, acc}

        {name, _meta, _args} = node, acc when is_atom(name) ->
          if name |> Atom.to_string() |> String.starts_with?("sigil_"),
            do: {:pruned, acc},
            else: {node, acc}

        text, acc when is_binary(text) ->
          {text, [text | acc]}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp prune_heex_comments(text) when is_binary(text), do: strip_comments(text)
  defp prune_heex_comments(node), do: node
end
