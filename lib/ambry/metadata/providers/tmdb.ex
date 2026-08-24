defmodule Ambry.Metadata.Providers.Tmdb do
  @moduledoc """
  Person-level provider backed by TMDB (themoviedb.org).

  Headshots (and often bios) for anyone with screen credits — many
  narrators are working actors, and it covers authors with TV/film
  credits too (Ty Franck again, via The Expanse). Complements the
  Wikidata/Wikipedia provider: TMDB's profile photos are high-quality
  and plentiful where Commons often has nothing.

  Needs a free API key (unavailable until configured — visible in the
  admin settings with a setup notice, not offered in import forms).
  """

  @behaviour Ambry.Metadata.Provider

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Provider.ConfigField
  alias Ambry.Metadata.Providers.Tmdb.Client

  @signup_url "https://www.themoviedb.org/settings/api"

  # original-size profile images; TMDB profiles are typically ~2000px tall
  @image_base_url "https://image.tmdb.org/t/p/original"

  @impl Provider
  def id, do: "tmdb"

  @impl Provider
  def display_name, do: "TMDB"

  @impl Provider
  def level, do: :person

  @impl Provider
  def capabilities, do: [:author_search, :author_details]

  @impl Provider
  def config_fields do
    [
      %ConfigField{
        key: :api_key,
        label: "API key",
        type: :secret,
        default: nil,
        help: "Free key from #{@signup_url}. The v3 key or the v4 read token."
      }
    ]
  end

  @impl Provider
  def available?(config), do: is_binary(config[:api_key]) and config[:api_key] != ""

  @impl Provider
  def config_notices(config) do
    if available?(config) do
      []
    else
      # info, not warning: this provider is a purely optional extra — an
      # unkeyed TMDB is a fine steady state, not a misconfiguration
      [{:info, "Optional. Paste a free API key from #{@signup_url} to enable TMDB headshots."}]
    end
  end

  @impl Provider
  def search_authors(query, config) do
    with {:ok, %{"results" => results}} <-
           Client.get_json("/search/person", [query: query, include_adult: false], config) do
      {:ok, Enum.map(results, &result_summary/1)}
    end
  end

  @impl Provider
  def author_details(person_id, config) do
    with {:ok, person} <- Client.get_json("/person/#{person_id}", [], config) do
      {:ok,
       Provider.Author.new(%{
         provider: id(),
         id: to_string(person["id"]),
         name: person["name"],
         description: presence(person["biography"]),
         image_url: image_url(person["profile_path"]),
         image_urls: profile_images(person_id, config)
       })}
    end
  end

  # TMDB keeps every headshot anyone has uploaded, not just the primary one,
  # and this is the single richest source of *alternatives* in the stack — a
  # working actor often has a dozen. Which matters because the primary is
  # frequently a wide shot or a red-carpet group photo that loses the face to
  # a circular crop.
  #
  # A failure here costs the extras, never the profile: the primary
  # `profile_path` is already in hand.
  defp profile_images(person_id, config) do
    case Client.get_json("/person/#{person_id}/images", [], config) do
      {:ok, %{"profiles" => profiles}} when is_list(profiles) ->
        profiles
        |> Enum.sort_by(&(&1["vote_average"] || 0), :desc)
        |> Enum.map(&image_url(&1["file_path"]))
        |> Enum.reject(&is_nil/1)

      _no_extras ->
        []
    end
  end

  # search listing: the person's known-for credits are the disambiguator
  # ("Acting — The Expanse, Avenue 5")
  defp result_summary(result) do
    Provider.Author.new(%{
      provider: id(),
      id: to_string(result["id"]),
      name: result["name"],
      description: known_for(result),
      image_url: image_url(result["profile_path"])
    })
  end

  defp known_for(result) do
    titles =
      for entry <- result["known_for"] || [],
          title = presence(entry["title"] || entry["name"]),
          do: title

    case {presence(result["known_for_department"]), titles} do
      {nil, []} -> nil
      {department, []} -> department
      {nil, titles} -> Enum.join(titles, ", ")
      {department, titles} -> "#{department} · #{Enum.join(titles, ", ")}"
    end
  end

  defp image_url(nil), do: nil
  defp image_url(profile_path), do: @image_base_url <> profile_path

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value
end
