defmodule TVHStatsWeb.PageController do
  use TVHStatsWeb, :controller

  alias TVHStats.Utils
  alias TVHStats.API.Client, as: APIClient

  @history_params_schema %{
    page: [type: :integer, default: 1, number: [min: 1]],
    size: [type: :integer, default: 20, in: [3, 20, 50, 100]],
    q: [type: :string, default: ""],
    date_from: [type: :string, default: ""],
    date_to: [type: :string, default: ""],
    channel: [type: :string, default: ""],
    user: [type: :string, default: ""],
    status: [type: :string, default: "all", in: ["all", "active", "finished"]]
  }

  def history(conn, params) do
    with {:ok, validated_params} <- Tarams.cast(params, @history_params_schema) do
      %{
        page: page,
        size: size,
        q: q,
        date_from: date_from,
        date_to: date_to,
        channel: channel,
        user: user,
        status: status
      } = validated_params

      timezone = Application.get_env(:tvhstats, :tvh_tz)

      users = APIClient.get_users()

      filters = %{
        "q" => q,
        "date_from" => date_from,
        "date_to" => date_to,
        "channel" => channel,
        "user" => user,
        "status" => status
      }

      subscriptions =
        Enum.map(TVHStats.Subscriptions.list_with_filters(page, size, filters), &parse_subscription(&1, timezone))

      subscription_count = TVHStats.Subscriptions.count_with_filters(filters)

      conn
      |> assign(:page_title, "History")
      |> assign(:subscriptions, subscriptions)
      |> assign(:page, page)
      |> assign(:page_size, size)
      |> assign(:next_page, page + 1)
      |> assign(:prev_page, page - 1)
      |> assign(:show_next_page, show_next_page?(page + 1, subscription_count, size))
      |> assign(:total_items, subscription_count)
      |> assign(:q, q)
      |> assign(:date_from, date_from)
      |> assign(:date_to, date_to)
      |> assign(:channel, channel)
      |> assign(:user, user)
      |> assign(:status, status)
      |> assign(:users, users)
      |> render("history.html")
    else
      {:error, errors} ->
        Plug.Conn.send_resp(conn, 400, Jason.encode!(errors))
    end
  end

  def get_graphs(conn, params) do
    # Parse date range from params, default to last 30 days
    days = case params["days"] do
      nil -> 30
      "" -> 30
      days_str -> case Integer.parse(days_str) do
        {days, _} when days > 0 and days <= 365 -> days
        _ -> 30
      end
    end

    conn
    |> assign(:page_title, "Graphs")
    |> assign(:selected_days, days)
    |> assign(:daily_play_count, get_daily_play_count(days))
    |> assign(:hourly_play_count, get_hourly_play_count(days))
    |> assign(:weekday_play_count, get_weekday_play_count(days))
    |> assign(:top_channels, get_top_channels(days))
    |> assign(:top_users, get_top_users(days))
    |> assign(:stream_type_distribution, get_stream_type_distribution(days))
    |> assign(:channel_watch_time, get_channel_watch_time(days))
    |> assign(:average_session_duration, get_average_session_duration(days))
    |> render("graphs.html")
  end

  def reset_history(conn, _params) do
    {deleted_count, _} = TVHStats.Subscriptions.reset_all()

    conn
    |> put_flash(:info, "History reset successfully. #{deleted_count} records deleted.")
    |> redirect(to: Routes.page_path(conn, :history))
  end

  defp show_next_page?(next_page, total_items, page_size) do
    next_page <= Float.ceil(total_items / page_size)
  end

  defp parse_subscription(subscription, timezone) do
    shifted_started_at = DateTime.shift_zone!(subscription.started_at, timezone)

    %{
      start_date: Calendar.strftime(shifted_started_at, "%Y-%m-%d"),
      start_time: Calendar.strftime(shifted_started_at, "%H:%M"),
      stop_time:
        if(subscription.stopped_at,
          do:
            subscription.stopped_at
            |> DateTime.shift_zone!(timezone)
            |> Calendar.strftime("%H:%M"),
          else: nil
        ),
      channel: subscription.channel,
      user: subscription.user,
      ip: subscription.ip,
      duration:
        DateTime.diff(
          if(subscription.stopped_at, do: subscription.stopped_at, else: DateTime.utc_now()),
          subscription.started_at,
          :minute
        )
    }
  end

  def get_daily_play_count(days \\ 30) do
    plays =
      days
      |> TVHStats.Subscriptions.get_daily_plays()
      |> Enum.into(%{})

    0..(days - 1)
    |> Stream.map(&Utils.datetime_n_days_ago/1)
    |> Stream.map(fn date -> {date, Calendar.strftime(date, "%d %b %Y")} end)
    |> Stream.map(fn
      {date, date_str} ->
        %{date: date, label: Calendar.strftime(date, "%b %d"), value: Map.get(plays, date_str, 0)}
    end)
    |> Enum.sort_by(&Map.get(&1, :date), {:asc, Date})
  end

  def get_hourly_play_count(days \\ 30) do
    plays =
      days
      |> TVHStats.Subscriptions.get_hourly_plays()
      |> Enum.map(fn {hour, value}-> {trunc(hour), value} end)
      |> Enum.into(%{})

    Enum.map(0..23, fn hour -> %{label: String.pad_leading("#{hour}", 2, "0"), value: Map.get(plays, hour, 0)} end)
  end

  def get_weekday_play_count(days \\ 30) do
    plays =
      days
      |> TVHStats.Subscriptions.get_weekday_plays()
      |> Enum.map(fn {hour, value}-> {trunc(hour), value} end)
      |> Enum.into(%{})

    Enum.map(1..7, fn weekday -> %{label: get_dow(weekday), value: Map.get(plays, weekday, 0)} end)
  end

  defp get_dow(1), do: "Monday"
  defp get_dow(2), do: "Tuesday"
  defp get_dow(3), do: "Wednesday"
  defp get_dow(4), do: "Thursday"
  defp get_dow(5), do: "Friday"
  defp get_dow(6), do: "Saturday"
  defp get_dow(7), do: "Sunday"

  def get_top_channels(days \\ 30) do
    TVHStats.Subscriptions.get_top_channels(days)
    |> Enum.map(fn %{"channel" => channel, "plays" => plays} ->
      %{label: channel, value: plays}
    end)
  end

  def get_top_users(days \\ 30) do
    TVHStats.Subscriptions.get_top_users(days)
    |> Enum.map(fn %{"user" => user, "plays" => plays} ->
      %{label: user, value: plays}
    end)
  end

  def get_stream_type_distribution(days \\ 30) do
    TVHStats.Subscriptions.get_stream_type_distribution(days)
  end

  def get_channel_watch_time(days \\ 30) do
    TVHStats.Subscriptions.get_channel_watch_time(days)
    |> Enum.map(fn %{"channel" => channel, "duration" => duration} ->
      %{label: channel, value: duration}
    end)
  end

  def get_average_session_duration(days \\ 30) do
    TVHStats.Subscriptions.get_average_session_duration(days)
  end
end
