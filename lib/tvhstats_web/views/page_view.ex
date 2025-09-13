defmodule TVHStatsWeb.PageView do
  use TVHStatsWeb, :view

  def get_last_item(page, size, total) when page * size > total, do: total
  def get_last_item(page, size, _total), do: page * size

  def fetch_chart_data(data) do
    Enum.map(data, fn %{value: value} -> value end)
  end

  def fetch_chart_labels(data) do
    Enum.map(data, fn %{label: label} -> label end)
  end

  def format_duration(seconds) when is_integer(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m #{secs}s"
      minutes > 0 -> "#{minutes}m #{secs}s"
      true -> "#{secs}s"
    end
  end

  def format_duration(_), do: "N/A"
end
