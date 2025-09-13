defmodule TVHStats.Subscriptions.Query do
  @moduledoc """
  Queries to filter Subscriptions
  """

  import Ecto.Query

  alias TVHStats.Subscriptions.Subscription
  alias TVHStats.Utils

  def get_all() do
    from(s in Subscription, order_by: [desc: :started_at])
  end

  def get_paginated(page, items \\ 20) do
    offset = (page - 1) * items

    from(
      s in Subscription,
      offset: ^offset,
      limit: ^items,
      order_by: [desc: :started_at]
    )
  end

  def get_paginated_with_filters(page, items \\ 20, filters \\ %{}) do
    offset = (page - 1) * items

    query = from(
      s in Subscription,
      offset: ^offset,
      limit: ^items,
      order_by: [desc: :started_at]
    )

    query
    |> apply_filters(filters)
  end

  def get_count_with_filters(filters \\ %{}) do
    query = from(s in Subscription, select: count(s.hash))
    query |> apply_filters(filters)
  end

  defp apply_filters(query, filters) do
    query
    |> apply_search_filter(Map.get(filters, "q", ""))
    |> apply_date_filter(Map.get(filters, "date_from", ""), Map.get(filters, "date_to", ""))
    |> apply_channel_filter(Map.get(filters, "channel", ""))
    |> apply_user_filter(Map.get(filters, "user", ""))
    |> apply_status_filter(Map.get(filters, "status", ""))
  end

  defp apply_search_filter(query, q) when q == "" or is_nil(q), do: query
  defp apply_search_filter(query, q) do
    search_term = "%#{String.downcase(q)}%"
    from(s in query,
      where: ilike(s.channel, ^search_term) or
             ilike(s.user, ^search_term) or
             ilike(s.ip, ^search_term) or
             ilike(s.client, ^search_term)
    )
  end

  defp apply_date_filter(query, from_date, to_date) do
    query
    |> apply_date_from_filter(from_date)
    |> apply_date_to_filter(to_date)
  end

  defp apply_date_from_filter(query, "") when "" == "", do: query
  defp apply_date_from_filter(query, nil), do: query
  defp apply_date_from_filter(query, date_str) do
    case DateTime.from_iso8601(date_str <> "T00:00:00Z") do
      {:ok, datetime, _} ->
        from(s in query, where: s.started_at >= ^datetime)
      _ ->
        query
    end
  end

  defp apply_date_to_filter(query, "") when "" == "", do: query
  defp apply_date_to_filter(query, nil), do: query
  defp apply_date_to_filter(query, date_str) do
    case DateTime.from_iso8601(date_str <> "T23:59:59Z") do
      {:ok, datetime, _} ->
        from(s in query, where: s.started_at <= ^datetime)
      _ ->
        query
    end
  end

  defp apply_channel_filter(query, "") when "" == "", do: query
  defp apply_channel_filter(query, nil), do: query
  defp apply_channel_filter(query, channel) do
    from(s in query, where: ilike(s.channel, ^"%#{channel}%"))
  end

  defp apply_user_filter(query, "") when "" == "", do: query
  defp apply_user_filter(query, nil), do: query
  defp apply_user_filter(query, user) do
    from(s in query, where: ilike(s.user, ^"%#{user}%"))
  end

  defp apply_status_filter(query, "all"), do: query
  defp apply_status_filter(query, nil), do: query
  defp apply_status_filter(query, "active") do
    from(s in query, where: is_nil(s.stopped_at))
  end
  defp apply_status_filter(query, "finished") do
    from(s in query, where: not is_nil(s.stopped_at))
  end
  defp apply_status_filter(query, _), do: query

  def get_count() do
    from(s in Subscription, select: count(s.hash))
  end

  def list_by_hash(hash_list) do
    from(s in Subscription, where: s.hash in ^hash_list)
  end

  def get_by_hash(hash) do
    from(s in Subscription, where: s.hash == ^hash)
  end

  def get_playing() do
    from(s in Subscription, where: is_nil(s.stopped_at))
  end

  def stop_all(hashes) do
    now = DateTime.utc_now()

    from(
      s in Subscription,
      where: s.hash in ^hashes,
      update: [set: [stopped_at: ^now, updated_at: ^now]]
    )
  end

  def get_play_count(field, last_n_days) do
    date = Utils.datetime_n_days_ago(last_n_days)

    from(
      s in Subscription,
      select: %{"plays" => count(s.hash)},
      where: s.started_at > ^date and not is_nil(s.stopped_at),
      group_by: ^field,
      order_by: [desc: count(s.hash)],
      limit: 5
    )
    |> add_field(field)
  end

  def get_play_duration(field, last_n_days) do
    date = Utils.datetime_n_days_ago(last_n_days)

    from(
      s in Subscription,
      select: %{
        "duration" => sum(fragment("EXTRACT(EPOCH FROM(? - ?))", s.stopped_at, s.started_at))
      },
      where: s.started_at > ^date and not is_nil(s.stopped_at),
      group_by: ^field,
      order_by: [desc: sum(s.stopped_at - s.started_at)],
      limit: 5
    )
    |> add_field(field)
  end

  def get_play_count_and_duration(field, last_n_days) do
    date = Utils.datetime_n_days_ago(last_n_days)

    from(
      s in Subscription,
      select: %{
        "plays" => count(s.hash),
        "duration" => sum(fragment("EXTRACT(EPOCH FROM(? - ?))", s.stopped_at, s.started_at))
      },
      where: s.started_at > ^date and not is_nil(s.stopped_at),
      group_by: ^field,
      order_by: [desc: count(s.hash)],
      limit: 5
    )
    |> add_field(field)
  end

  def get_play_activity(last_n_days) do
    date = Utils.datetime_n_days_ago(last_n_days)

    from(
      s in Subscription,
      select: %{"channel" => s.channel, "users" => count(s.user)},
      where: s.started_at > ^date and not is_nil(s.stopped_at),
      group_by: s.channel,
      order_by: [desc: count(s.user)],
      limit: 5
    )
  end

  @doc "to_char function for formatting datetime as dd MON YYYY"
  defmacro to_char(field, format) do
    quote do
      fragment("to_char(?, ?)", unquote(field), unquote(format))
    end
  end

  def get_daily_activity(last_n_days) do
    date = Utils.datetime_n_days_ago(last_n_days)

    from(
      s in Subscription,
      select: {to_char(s.started_at, "dd Mon YYYY"), count(s.hash)},
      where: s.started_at > ^date,
      group_by: to_char(s.started_at, "dd Mon YYYY")
    )
  end

  def get_hourly_activity(last_n_days) do
    date = Utils.datetime_n_days_ago(last_n_days)

    from(
      s in Subscription,
      select: {(fragment("date_part('hour', ?)", s.started_at)), count(s.hash)},
      where: s.started_at > ^date,
      group_by: (fragment("date_part('hour', ?)", s.started_at))
    )
  end

  def get_weekday_activity(last_n_days) do
    date = Utils.datetime_n_days_ago(last_n_days)

    from(
      s in Subscription,
      select: {(fragment("date_part('isodow', ?)", s.started_at)), count(s.hash)},
      where: s.started_at > ^date,
      group_by: (fragment("date_part('isodow', ?)", s.started_at))
    )
  end


  defp add_field(q, :user) do
    select_merge(q, [s], %{"user" => s.user})
  end

  defp add_field(q, :channel) do
    select_merge(q, [s], %{"channel" => s.channel})
  end

  def get_stream_type_distribution(last_n_days) do
    date = Utils.datetime_n_days_ago(last_n_days)

    from(
      s in Subscription,
      select: {s.stream_type, count(s.hash)},
      where: s.started_at > ^date,
      group_by: s.stream_type
    )
  end

  def get_average_session_duration(last_n_days) do
    date = Utils.datetime_n_days_ago(last_n_days)

    from(
      s in Subscription,
      select: %{
        avg_duration: avg(fragment("EXTRACT(EPOCH FROM(? - ?))", s.stopped_at, s.started_at))
      },
      where: s.started_at > ^date and not is_nil(s.stopped_at)
    )
  end
end
