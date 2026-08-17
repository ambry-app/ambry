defmodule AmbryWeb.Admin.ProvenanceHints do
  @moduledoc """
  Server-side tracking of which pending form values were accepted from a
  metadata provider, so that saving records provider provenance (unlocked)
  for accepted suggestions and manual provenance (locked) for typed edits —
  see `Ambry.Provenance`.

  Hints live in socket assigns, never in browser params. Each hint watches
  the form param carrying its value and dies the moment the operator edits
  that value: the field then saves as an ordinary manual edit.
  """

  # import-payload keys that never map to a tracked scalar field themselves
  @non_field_keys ~w(image_path image_type image_import_url)

  @doc """
  Builds hints from a provider-import payload: one per scalar param (watched
  under its own name), plus — when the payload carries an image URL import —
  one for `image_path` watching `image_import_url` (the actual path is only
  set at submit time, after the download). List params (associations) are
  structural and never hinted.
  """
  def from_import(params, source, record \\ nil) do
    scalar_hints =
      for {key, value} <- params,
          scalar?(value),
          key not in @non_field_keys,
          into: %{} do
        {key, %{source: source, record: record, watch: key, value: normalize(value)}}
      end

    case params do
      %{"image_type" => "url_import", "image_import_url" => url} ->
        Map.put(scalar_hints, "image_path", %{
          source: source,
          record: record,
          watch: "image_import_url",
          value: normalize(url)
        })

      # The file's own art has no URL to watch, so the hint watches the
      # choice itself: it survives until the operator picks something else.
      %{"image_type" => "embedded"} ->
        Map.put(scalar_hints, "image_path", %{
          source: source,
          record: record,
          watch: "image_type",
          value: "embedded"
        })

      _params ->
        scalar_hints
    end
  end

  @doc """
  A hint for a structural list (authors, series, narrators) filled from an
  accepted entity proposal. It watches nothing — later hand-edits to the
  list don't undo the fact that the provider proposed its members — and it
  carries no record ref, since a list's rows can come from several.
  """
  def for_list(hints, field, source) do
    Map.put(hints, field, %{source: source, record: nil, watch: nil, value: nil})
  end

  @doc """
  Drops hints whose watched param no longer carries the accepted value.
  Call on every validate and once more with the submit params.
  """
  def prune(hints, form_params) do
    hints
    |> Enum.reject(fn {field, hint} ->
      edited?(hint, form_params) or
        (field == "image_path" and image_source_changed?(hint, form_params))
    end)
    |> Map.new()
  end

  defp edited?(%{watch: nil}, _params), do: false

  defp edited?(hint, params) do
    case Map.fetch(params, hint.watch) do
      {:ok, value} -> normalize(value) != hint.value
      :error -> false
    end
  end

  # A cover accepted as a URL import is undone by switching the picker to an
  # upload, and `edited?/2` cannot see that: the URL sits in the params
  # untouched while something else becomes the answer.
  #
  # Only that hint. A cover taken from the file's own art watches
  # `image_type` itself, so switching away from it is an edit like any other
  # — and this rule, written when a URL was the only way a provider could
  # give you a picture, used to throw that hint away the moment it was made.
  defp image_source_changed?(%{watch: "image_import_url"}, %{"image_type" => type}),
    do: type != "url_import"

  defp image_source_changed?(_hint, _params), do: false

  @doc "The `provenance:` opts value for a save: field name → source (with its record ref, when known)."
  def sources(hints) do
    Map.new(hints, fn
      {field, %{record: nil} = hint} -> {field, hint.source}
      {field, hint} -> {field, %{"source" => hint.source, "record" => hint.record}}
    end)
  end

  # association params arrive as lists/maps and are never hinted — but
  # structs (%Date{} from published imports) are maps too, and ARE scalar
  # values (dropping them recorded accepted dates as manual edits)
  defp scalar?(value), do: not is_list(value) and (not is_map(value) or is_struct(value))

  defp normalize(value), do: to_string(value)
end
