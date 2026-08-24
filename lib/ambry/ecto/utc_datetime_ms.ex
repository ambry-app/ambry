defmodule Ambry.Ecto.UtcDateTimeMs do
  @moduledoc """
  A UTC datetime type with exactly millisecond precision.

  Errors on a DateTime with any other precision: supplying one with the right
  precision is the caller's job.

      DateTime.utc_now() |> DateTime.truncate(:millisecond)

  Supports autogeneration, so `timestamps(type: Ambry.Ecto.UtcDateTimeMs)`
  works.

  """
  use Ecto.Type

  @impl true
  def type, do: :utc_datetime_usec

  @doc """
  Generates a UTC DateTime with millisecond precision, for `timestamps/1`.
  """
  @impl true
  def autogenerate, do: DateTime.utc_now() |> DateTime.truncate(:millisecond)

  def from_unix!(microseconds, :microsecond) do
    microseconds |> DateTime.from_unix!(:microsecond) |> DateTime.truncate(:millisecond)
  end

  @impl true
  def cast(%DateTime{microsecond: {_, 3}} = dt), do: {:ok, dt}

  def cast(%DateTime{microsecond: {_, precision}}),
    do: {:error, message: "expected millisecond precision (3), got: #{precision}"}

  def cast(_), do: :error

  @impl true
  def load(%DateTime{} = dt), do: {:ok, dt |> DateTime.truncate(:millisecond)}

  def load(%NaiveDateTime{} = ndt),
    do: {:ok, DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.truncate(:millisecond)}

  def load(_), do: :error

  @impl true
  def dump(%DateTime{microsecond: {_, 3}} = dt), do: {:ok, dt}

  def dump(%DateTime{microsecond: {_, precision}}),
    do: {:error, message: "expected millisecond precision (3), got: #{precision}"}

  def dump(_), do: :error
end
