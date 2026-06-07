defmodule Ambry.Fake do
  @moduledoc """
  Tiny in-repo replacement for the bits of the `faker` library we used in tests
  and factories. Generates plausible-but-random data; not locale-aware.
  """
  use Boundary, top_level?: true, check: [in: false, out: false]

  @first_names ~w(
    Alice Amara Aria Benjamin Caleb Camila Chloe Daniel Diego Elena Eli Emma
    Ethan Fatima Felix Grace Hana Henry Ines Isaac Ivy Jasmine Julian Kai
    Lena Leo Lucas Maya Mateo Nadia Noah Olivia Omar Priya Quinn Ravi Sofia
    Theo Uma Victor Wren Xavier Yara Zoe
  )

  @last_names ~w(
    Abbott Bauer Carrasco Delgado Espinoza Fischer Gallagher Haddad Ibarra
    Jensen Kowalski Lindqvist Mbeki Nakamura Okafor Petrov Quintana Rosenberg
    Sato Thornton Underwood Vasquez Whitfield Xu Yoon Zimmerman Ashworth
    Beaumont Castellano Donovan
  )

  @lorem_words ~w(
    lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod
    tempor incididunt ut labore et dolore magna aliqua enim ad minim veniam
    quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo
    consequat duis aute irure in reprehenderit voluptate velit esse cillum
    fugiat nulla pariatur excepteur sint occaecat cupidatat non proident
  )

  @company_suffixes ~w(Inc LLC Group Holdings Partners Industries Labs Studios Media Press)

  @email_domains ~w(example.com example.org test.local mail.test)

  @doc "A full name, e.g. \"Maya Thornton\"."
  def full_name, do: "#{Enum.random(@first_names)} #{Enum.random(@last_names)}"

  @doc "A last name, e.g. \"Thornton\"."
  def last_name, do: Enum.random(@last_names)

  @doc "A plausible email address."
  def email do
    local =
      "#{Enum.random(@first_names)}.#{Enum.random(@last_names)}#{integer(1, 999)}"
      |> String.downcase()

    "#{local}@#{Enum.random(@email_domains)}"
  end

  @doc "A single lorem-ipsum word."
  def word, do: Enum.random(@lorem_words)

  @doc "A capitalized sentence of lorem-ipsum words ending in a period."
  def sentence(word_count \\ integer(4, 9)) do
    words = Enum.map(1..word_count, fn _ -> word() end)
    String.capitalize(Enum.join(words, " ")) <> "."
  end

  @doc "A paragraph made of a few sentences."
  def paragraph(sentence_count \\ integer(2, 4)) do
    Enum.map_join(1..sentence_count, " ", fn _ -> sentence() end)
  end

  @doc "A company name, e.g. \"Castellano Labs\"."
  def company_name, do: "#{Enum.random(@last_names)} #{Enum.random(@company_suffixes)}"

  @doc "A date between today and `days` ago (inclusive)."
  def date_backward(days) when is_integer(days) and days >= 0 do
    Date.add(Date.utc_today(), -Enum.random(0..days))
  end

  @doc "A random integer in `min..max` (inclusive)."
  def integer(min, max) when is_integer(min) and is_integer(max) and min <= max do
    Enum.random(min..max)
  end

  @doc "A random float in the range [0.0, 1.0)."
  def uniform, do: :rand.uniform()
end
