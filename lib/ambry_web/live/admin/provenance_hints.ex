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
  def from_import(params, source) do
    scalar_hints =
      for {key, value} <- params,
          not is_list(value),
          not is_map(value),
          key not in @non_field_keys,
          into: %{} do
        {key, %{source: source, watch: key, value: normalize(value)}}
      end

    case params do
      %{"image_type" => "url_import", "image_import_url" => url} ->
        Map.put(scalar_hints, "image_path", %{
          source: source,
          watch: "image_import_url",
          value: normalize(url)
        })

      _params ->
        scalar_hints
    end
  end

  @doc """
  Drops hints whose watched param no longer carries the accepted value.
  Call on every validate and once more with the submit params.
  """
  def prune(hints, form_params) do
    hints
    |> Enum.reject(fn {field, hint} ->
      edited?(hint, form_params) or
        (field == "image_path" and image_source_changed?(form_params))
    end)
    |> Map.new()
  end

  defp edited?(hint, params) do
    case Map.fetch(params, hint.watch) do
      {:ok, value} -> normalize(value) != hint.value
      :error -> false
    end
  end

  defp image_source_changed?(params) do
    case params do
      %{"image_type" => type} -> type != "url_import"
      _params -> false
    end
  end

  @doc "The `provenance:` opts value for a save: field name → source."
  def sources(hints), do: Map.new(hints, fn {field, hint} -> {field, hint.source} end)

  defp normalize(value), do: to_string(value)
end
