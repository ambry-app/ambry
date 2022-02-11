defmodule Ambry.SeriesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ambry.Series` context.
  """

  def unique_series_name, do: "Series #{System.unique_integer()}"

  def valid_series_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_series_name()
    })
  end

  def series_fixture(attrs \\ %{}) do
    {:ok, series} =
      attrs
      |> valid_series_attributes()
      |> Ambry.Series.create_series()

    series
  end
end
