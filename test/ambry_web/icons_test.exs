defmodule AmbryWeb.IconsTest do
  @moduledoc """
  Every icon name written in a template must exist in the vendored set.

  The icon component renders `fa-<name>` as a CSS mask; a name with no
  vendored SVG behind it renders a blank, correctly-sized-or-zero-width
  nothing — no warning, no crash, just a missing glyph and mysterious
  spacing. This has shipped twice. Dynamic names (`name={...}`) aren't
  covered; string literals are the overwhelmingly common case.

  **Both spellings.** A component that takes an icon and hands it on names
  the attribute `icon`, and every row action in the admin is written that
  way — nineteen literals this scanned straight past, one of which was not
  vendored and shipped blank. A rule that checks only the spelling it was
  written for has a hole the shape of every other caller.

  One failure mode lives below this test's reach: the Tailwind plugin
  `readdirSync`s the vendor dir when the *watcher* starts, so an SVG
  vendored while the dev server runs passes here yet still renders blank
  live until the watcher reloads its config — `touch
  assets/tailwind.config.js` after vendoring a new icon. Fresh builds
  (CI, prod, a restarted server) are unaffected.
  """

  use ExUnit.Case, async: true

  @vendor Path.expand("../../assets/vendor/fontawesome", __DIR__)
  @sources Path.expand("../../lib/ambry_web", __DIR__)

  test "every fa- icon literal has a vendored SVG" do
    used =
      @sources
      |> Path.join("**/*.{ex,heex}")
      |> Path.wildcard()
      |> Enum.flat_map(fn file ->
        for [name] <-
              Regex.scan(~r/(?:name|icon)="fa-([a-z0-9-]+)"/, File.read!(file),
                capture: :all_but_first
              ),
            do: {name, Path.relative_to_cwd(file)}
      end)

    missing =
      for {name, file} <- Enum.uniq(used),
          path = vendored_path(name),
          not File.exists?(Path.join(@vendor, path)),
          do: "#{name} (#{file}) — expected assets/vendor/fontawesome/#{path}"

    assert missing == [],
           "icons referenced in templates but not vendored:\n  " <> Enum.join(missing, "\n  ")
  end

  defp vendored_path("brands-" <> name), do: "brands/#{name}.svg"
  defp vendored_path(name), do: "solid/#{name}.svg"
end
