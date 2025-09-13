defmodule TVHStatsWeb.HomeLive.Home do
  @moduledoc """
  Home screen for app, shows current streams with live updates and stats.
  """

  use TVHStatsWeb, :live_view

  alias TVHStats.Subscriptions
  alias TVHStats.API.Client, as: APIClient
  alias TVHStats.Utils.Seconds

  @default_timezone "Etc/UTC"
  @subscriptions_topic "active_subs"

  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
  Phoenix.PubSub.subscribe(TVHStats.PubSub, @subscriptions_topic)
  TVHStatsWeb.Endpoint.subscribe(@subscriptions_topic)

  socket
  |> assign(channel_usage_30d: Subscriptions.get_count_and_duration_for_last_n(:channel, 30))
  |> assign(user_usage_30d: Subscriptions.get_count_and_duration_for_last_n(:user, 30))
  |> assign(play_activity_30d: Subscriptions.get_activity_for_last_n(30))
      else
        socket
  |> assign(channel_usage_30d: [])
  |> assign(user_usage_30d: [])
        |> assign(play_activity_30d: [])
      end

    # Seed Active streams immediately from API
    tz = Application.get_env(:tvhstats, :tvh_tz)
    now_streams = APIClient.get_streams()
    now_entries = Map.get(now_streams, "entries", [])
    parsed_entries = Enum.map(now_entries, &parse_subscription(&1, tz))

    {
      :ok,
      socket
      |> assign(page_title: "Home")
      |> assign(timezone: tz)
      |> assign(active_subscriptions: parsed_entries)
      |> assign(subscriptions_summary: get_subscriptions_summary(now_entries))
  |> assign(server_info: APIClient.get_server_info())
  |> assign(server_host: Application.get_env(:tvhstats, :tvh_host))
    }
  end

  def handle_info({"active_subscriptions", subscriptions}, socket) do
    {
      :noreply,
      socket
      |> assign(
        active_subscriptions:
          Enum.map(subscriptions, &parse_subscription(&1, socket.assigns.timezone))
      )
      |> assign(subscriptions_summary: get_subscriptions_summary(subscriptions))
    }
  end

  defp parse_subscription(
         %{
           "start" => start,
           "username" => _username,
           "channel" => _channel,
           "in" => bytes_in,
           "total_in" => total_bytes_in
         } = subscription,
         timezone
       ) do
    subscription
  |> Map.put("in_bps", bytes_in)
  |> Map.put("in", parse_bandwidth(bytes_in))
    |> Map.put("total_in", parse_transfer(total_bytes_in))
    |> Map.put("started_at", parse_timestamp(start, timezone))
    |> Map.put("runtime", parse_runtime(start))
  end

  defp parse_subscription(
         %{
           "start" => start,
           "channel" => _channel,
           "in" => bytes_in,
           "total_in" => total_bytes_in,
           "hostname" => ip
         } = subscription,
         timezone
       ) do
    subscription
  |> Map.put("in_bps", bytes_in)
  |> Map.put("in", parse_bandwidth(bytes_in))
    |> Map.put("total_in", parse_transfer(total_bytes_in))
    |> Map.put("started_at", parse_timestamp(start, timezone))
    |> Map.put("runtime", parse_runtime(start))
    |> Map.put("username", "anonymous@" <> ip)
  end

  defp parse_bandwidth(bits) do
    Sizeable.filesize(bits, bits: true)
  end

  defp parse_transfer(bytes) do
    Sizeable.filesize(bytes)
  end

  defp parse_timestamp(unix_timestamp, timezone \\ @default_timezone) do
    unix_timestamp
    |> DateTime.from_unix!()
    |> DateTime.shift_zone!(timezone)
  end

  defp parse_runtime(datetime) do
    DateTime.diff(DateTime.utc_now(), parse_timestamp(datetime), :second)
  end

  defp get_subscriptions_summary(subscriptions) do
    summary =
      Enum.reduce(
        subscriptions,
        %{streams: 0, bandwidth: 0},
        fn sub, %{streams: s_acc, bandwidth: b_acc} ->
          raw_in = Map.get(sub, "in_bps") || Map.get(sub, "in") || 0
          %{streams: s_acc + 1, bandwidth: b_acc + raw_in}
        end
      )

    Map.put(summary, :bandwidth, parse_bandwidth(summary[:bandwidth]))
  end

  def format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  def format_runtime(seconds) do
    Seconds.to_hh_mm_ss(seconds)
  end

  def format_duration(seconds) do
    Seconds.to_hh_mm(seconds)
  end

  def encode_uri(channel) do
    :uri_string.quote(channel)
  end

  def get_value(assigns, key) do
    Map.get(assigns, key)
  end
end
