defmodule TVHStats.API.Client do
  @moduledoc """
  Module used to interface with Tvheadend API
  """

  require Logger

  alias TVHStats.Subscriptions.Utils, as: SubscriptionUtils

  @invalid_clients ["epggrab", "scan"]
  @page_size 100

  def get_streams() do
    res =
      "/status/subscriptions"
      |> build_request()
      |> send_request()

    case res do
      {:ok, response} ->
        %{"entries" => subscriptions, "totalCount" => _count} = response

        subscriptions =
          subscriptions
          |> Enum.map(&parse_subscription(&1))
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1["start"])

        %{
          "entries" => subscriptions,
          "totalCount" => length(subscriptions)
        }

      {:error, _reason} ->
        %{"entries" => [], "totalCount" => 0}
    end
  end

  @doc """
  Returns Tvheadend server information from /api/serverinfo

  Example response:
  %{"sw_version" => "4.3-2426~gd1fb6da0a-dirty", "api_version" => 19, "name" => "Tvheadend", "capabilities" => [...]}
  """
  def get_server_info() do
    res =
      "/serverinfo"
      |> build_request()
      |> send_request()

    case res do
      {:ok, response} -> response
      {:error, _reason} -> %{}
    end
  end

  def get_channels(channels \\ [], page \\ 0, processed \\ 0) do
    res =
      "/channel/grid"
      |> build_request(%{start: page * @page_size, limit: @page_size})
      |> send_request()

    case res do
      {:ok, response} ->
        %{"entries" => recv_channels, "total" => _total} = response

        if length(recv_channels) > 0 do
          get_channels(channels ++ recv_channels, page + 1, processed + length(channels))
        else
          channels
        end

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Returns a flat list of channels from /api/channel/list

  Each entry is expected to contain at least a "name" field.
  """
  def get_channel_list() do
    res =
      "/channel/list"
      |> build_request()
      |> send_request()

    channels =
      case res do
        {:ok, %{"entries" => entries}} when is_list(entries) ->
          entries

        {:ok, list} when is_list(list) ->
          list

        _ ->
          []
      end
      |> Enum.map(&normalize_channel/1)
      |> Enum.filter(&(is_binary(&1["name"]) and &1["name"] != ""))
      |> Enum.uniq_by(& &1["name"])
      |> sort_channels()

    case channels do
      [] ->
        # Fallback to grid API if list returns empty
        get_channels()
        |> Enum.map(&normalize_channel/1)
        |> Enum.filter(&(is_binary(&1["name"]) and &1["name"] != ""))
        |> Enum.uniq_by(& &1["name"])
        |> sort_channels()

      _ ->
        channels
    end
  end

  @doc """
  Returns channels from /api/channel/grid (all pages), normalized and sorted by number.
  """
  def get_channel_grid() do
    get_channels()
    |> Enum.map(&normalize_channel/1)
    |> Enum.filter(&(is_binary(&1["name"]) and &1["name"] != ""))
    |> Enum.uniq_by(& &1["name"])
    |> sort_channels()
  end

  @doc """
  Returns channel tags from /api/channeltag/list.

  Each tag typically has at least a name and uuid. We normalize shape and
  sort by name.
  """
  def get_channel_tags() do
    res =
      "/channeltag/list"
      |> build_request()
      |> send_request()

    tags =
      case res do
        {:ok, %{"entries" => entries}} when is_list(entries) -> entries
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    tags
    |> Enum.map(fn t ->
      name = t["name"] || t["title"] || t["val"]
      uuid = t["uuid"] || t["id"]
      key = t["key"] || t["id"]
      index = parse_int(t["index"] || t["order"] || t["num"] || t["priority"])
      %{ "name" => name, "uuid" => uuid, "key" => key, "index" => index }
    end)
    |> Enum.filter(&(is_binary(&1["name"]) and &1["name"] != ""))
    |> Enum.sort_by(fn t -> {is_nil(t["index"]), t["index"] || 0, String.downcase(t["name"]) } end)
  end

  @doc """
  Returns channel tags from /api/channeltag/grid across all pages, normalized
  with index information and sorted by index ascending, then by name.
  """
  def get_channel_tags_grid(tags \\ [], page \\ 0) do
    res =
      "/channeltag/grid"
      |> build_request(%{start: page * @page_size, limit: @page_size})
      |> send_request()

    case res do
      {:ok, %{"entries" => recv_tags} = _response} when is_list(recv_tags) and length(recv_tags) > 0 ->
        get_channel_tags_grid(tags ++ recv_tags, page + 1)

      {:ok, %{"entries" => _recv_tags}} ->
        # No more pages; normalize and sort
        tags
        |> Enum.map(fn t ->
          name = t["name"] || t["title"] || t["val"]
          uuid = t["uuid"] || t["id"]
          key = t["key"] || t["id"]
          index = parse_int(t["index"] || t["order"] || t["num"] || t["priority"])
          %{ "name" => name, "uuid" => uuid, "key" => key, "index" => index }
        end)
        |> Enum.filter(&(is_binary(&1["name"]) and &1["name"] != ""))
        |> Enum.uniq_by(& &1["uuid"] || &1["key"] || &1["name"])
        |> Enum.sort_by(fn t -> {is_nil(t["index"]), t["index"] || 0, String.downcase(t["name"]) } end)

      {:error, _} ->
        # Fallback to list version if grid fails
        get_channel_tags()
    end
  end

  defp normalize_channel(%{"name" => _} = ch) do
    Map.update(ch, "number", parse_int(ch["number"]), fn v -> parse_int(v) end)
  end
  defp normalize_channel(ch) do
    name = ch["name"] || ch["channel"] || ch["svcname"] || ch["chname"] || ch["title"] || ch["val"]
    number = ch["number"] || ch["chnum"] || ch["lcn"] || ch["index"] || ch["chno"]
    ch
    |> Map.put_new("name", name)
    |> Map.put("number", parse_int(number))
  end

  defp parse_int(nil), do: nil
  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_float(v), do: trunc(v)
  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp sort_channels(channels) do
    {with_num, without_num} = Enum.split_with(channels, fn c -> is_integer(c["number"]) end)
    with_num = Enum.sort_by(with_num, & &1["number"])
    without_num = Enum.sort_by(without_num, &String.downcase(&1["name"]))
    with_num ++ without_num
  end

  defp parse_subscription(%{"title" => client}) when client in @invalid_clients, do: nil

  defp parse_subscription(subscription) do
    hash = SubscriptionUtils.generate_hash(subscription)

    stream_type =
      subscription
      |> Map.get("title")
      |> String.downcase()

    subscription
    |> Map.put("hash", hash)
    |> Map.put("stream_type", stream_type)
  end

  defp build_request(endpoint, query_params \\ nil) do
    Finch.build(:get, "#{url()}#{endpoint}#{params(query_params)}", headers())
  end

  defp send_request(request) do
    case Finch.request(request, HttpClient) do
      {:ok, %Finch.Response{body: body, status: 200}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %Finch.Response{status: 400}} ->
        Logger.error("Bad request. Malformed query.")
        {:error, :bad_request}

      {:ok, %Finch.Response{status: 401}} ->
        Logger.error("Request was not authorized. Please check your credentials.")
        {:error, :not_authenticated}

      {:ok, %Finch.Response{status: 500}} ->
        Logger.error("There was an error processing the request. Check your server for logs.")
        {:error, :server_error}

      {:ok, %Finch.Response{status: _status}} ->
        Logger.error("There was an unknown error processing the request.")
        {:error, :unknown_error}

      {:error, %Mint.TransportError{reason: reason}} ->
        Logger.error(
          "There was an error sending the request: #{reason}. Please check you set your server correctly."
        )

        {:error, reason}
    end
  end

  defp url() do
    host = Application.get_env(:tvhstats, :tvh_host)
    port = Application.get_env(:tvhstats, :tvh_port)
    schema = if Application.get_env(:tvhstats, :tvh_use_https), do: "https", else: "http"

    "#{schema}://#{host}:#{port}/api"
  end

  defp headers() do
    user = Application.get_env(:tvhstats, :tvh_user)
    password = Application.get_env(:tvhstats, :tvh_password)

    [{"Authorization", "Basic #{Base.encode64("#{user}:#{password}")}"}]
  end

  defp params(nil), do: ""

  defp params(query_params) do
    encoded_query_params =
      query_params
      |> UriQuery.params()
      |> URI.encode_query()

    "?#{encoded_query_params}"
  end
end
