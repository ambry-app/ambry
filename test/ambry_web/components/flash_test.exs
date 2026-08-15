defmodule AmbryWeb.FlashTest do
  @moduledoc """
  Flashes are toasts now: top centre, quiet, and gone on their own.

  They used to be solid lime and red slabs pinned to the top *right*, which
  is where the admin keeps the user menu and the job indicator, and they
  stayed until clicked.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AmbryWeb.CoreComponents

  defp group(flash), do: render_component(&CoreComponents.flash_group/1, flash: flash)

  defp doc(html), do: Floki.parse_document!(html)

  test "renders the message" do
    html = group(%{"info" => "Added to the library."})

    assert html =~ "Added to the library."
  end

  # The old markup led with a "Success!" / "Error!" heading above the message,
  # which said nothing the icon doesn't and made a one-line toast two lines.
  test "carries no severity heading" do
    html = group(%{"info" => "Saved.", "error" => "Nope."})

    refute html =~ "Success!"
    refute html =~ "Error!"
  end

  test "the rail is centred and does not swallow clicks when empty" do
    [rail] = %{} |> group() |> doc() |> Floki.find("#flash-group")

    classes = Floki.attribute(rail, "class") |> List.first()

    assert classes =~ "left-1/2"
    assert classes =~ "-translate-x-1/2"
    assert classes =~ "pointer-events-none"
    refute classes =~ "right-2"
  end

  test "a real flash dismisses itself, and says how long it waits" do
    info = %{"info" => "Saved."} |> group() |> doc() |> Floki.find("#flash-info")
    error = %{"error" => "Nope."} |> group() |> doc() |> Floki.find("#flash-error")

    assert [after_info] = Floki.attribute(info, "data-dismiss-after")
    assert [after_error] = Floki.attribute(error, "data-dismiss-after")

    assert String.to_integer(after_info) > 0
    # An error is likelier to be worth reading twice.
    assert String.to_integer(after_error) > String.to_integer(after_info)

    assert Floki.attribute(info, "phx-hook") == ["auto-dismiss"]
  end

  # These are not a report of something that happened, they are the current
  # state of the socket. Timing one out would claim the connection came back.
  test "the connection toasts never dismiss themselves" do
    html = doc(group(%{}))

    for id <- ["#client-error", "#server-error"] do
      toast = Floki.find(html, id)

      assert toast != [], "expected #{id} to be rendered"
      assert Floki.attribute(toast, "data-dismiss-after") == []
      assert Floki.attribute(toast, "phx-hook") == []
    end
  end

  # `[hidden] { display: none }` comes from the UA stylesheet, so ANY
  # author-level display utility on the same element outranks it. A `flex`
  # here once made both connection toasts visible on every navigation, for
  # the moment between first paint and `phx-connected` firing — too brief to
  # read and impossible to miss.
  @display_utilities ~w(flex inline-flex block inline-block grid inline-grid table contents)

  test "nothing hidden by attribute carries a display utility" do
    html = doc(group(%{}))

    for id <- ["#client-error", "#server-error"] do
      toast = Floki.find(html, id)

      assert Floki.attribute(toast, "hidden") != [],
             "expected #{id} to be hidden until the socket says otherwise"

      classes =
        toast |> Floki.attribute("class") |> List.first() |> to_string() |> String.split()

      assert classes -- @display_utilities == classes,
             "#{id} carries a display utility, which defeats its `hidden` attribute: " <>
               inspect(classes -- (classes -- @display_utilities))
    end
  end

  # Severity is the icon's job (design language §8). A solid bright fill was
  # the loudest thing on any page it appeared over, for a message that is
  # usually "saved".
  test "the box is the ordinary floating-layer fill, not a coloured slab" do
    classes =
      %{"error" => "Nope."}
      |> group()
      |> doc()
      |> Floki.find("#flash-error")
      |> Floki.attribute("class")
      |> List.first()

    assert classes =~ "bg-zinc-900"
    refute classes =~ "bg-red-400 "
  end
end
