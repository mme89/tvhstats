defmodule TVHStatsWeb.ChannelsLive do
  use TVHStatsWeb, :live_view

  alias TVHStats.API.Client, as: APIClient

  @impl true
  def mount(_params, _session, socket) do
    channels = APIClient.get_channel_grid()
  # Prefer grid API to obtain tag index/order for sorting and display
  tags = APIClient.get_channel_tags_grid()
    pad =
      tags
      |> Enum.map(& &1["index"])
      |> Enum.filter(&is_integer/1)
      |> case do
        [] -> 0
        idxs ->
          idxs
          |> Enum.max()
          |> Integer.to_string()
          |> String.length()
      end

    {:ok,
     socket
     |> assign(page_title: "Channels")
     |> assign(channels: channels)
     |> assign(tags: tags)
  |> assign(tag_index_pad: pad)
  |> assign(tags_open: false)
     |> assign(q: "")
     |> assign(selected_tag: "")
     |> assign(filtered_channels: channels)}
  end

  @impl true
  def handle_event("filters", params, socket) do
    q = Map.get(params, "q", "")
  tag = Map.get(params, "tag", socket.assigns.selected_tag || "")

    filtered = apply_filters(socket.assigns.channels, q, tag)

    {:noreply,
     socket
     |> assign(q: q, selected_tag: tag, filtered_channels: filtered)}
  end

  @impl true
  def handle_event("tags_toggle", _params, socket) do
    {:noreply, assign(socket, :tags_open, !socket.assigns.tags_open)}
  end

  @impl true
  def handle_event("tags_close", _params, socket) do
    {:noreply, assign(socket, :tags_open, false)}
  end

  @impl true
  def handle_event("select_tag", %{"id" => id}, socket) do
    q = socket.assigns.q
    filtered = apply_filters(socket.assigns.channels, q, id)
    {:noreply,
     socket
     |> assign(selected_tag: id, filtered_channels: filtered, tags_open: false)}
  end

  defp apply_filters(channels, q, tag) do
    q = (q || "") |> String.downcase() |> String.trim()
    tag = tag || ""

    Enum.filter(channels, fn ch ->
      name = String.downcase(to_string(ch["name"]))
      num = case ch["number"] do
        nil -> ""
        n when is_integer(n) -> Integer.to_string(n)
        n -> to_string(n)
      end

      query_ok = q == "" or String.contains?(name, q) or String.contains?(num, q)
      tag_ok = tag == "" or channel_has_tag?(ch, tag)
      query_ok and tag_ok
    end)
  end

  defp channel_has_tag?(ch, tag_id) do
    tags = ch["tags"] || ch["tag"] || ch["channeltags"] || ch["channeltag"] || []
    cond do
      is_list(tags) -> Enum.any?(tags, &(to_string(&1) == to_string(tag_id)))
      is_binary(tags) or is_integer(tags) -> to_string(tags) == to_string(tag_id)
      is_map(tags) ->
        v = tags["uuid"] || tags["key"] || tags["id"] || tags[:uuid] || tags[:key] || tags[:id]
        to_string(v || "") == to_string(tag_id)
      true -> false
    end
  end

  @impl true
  def render(assigns) do
  ~H"""
  <h3 class="text-white">Channels</h3>
  <p class="text-sm text-gray-400 mt-1">Click channel icons to open streams in TVHeadend</p>

  <div class="text-white pt-2 space-y-3">
  <form phx-change="filters" class="flex flex-wrap items-center gap-2">
  <input type="text" name="q" value={@q} placeholder="Search channels or numbers" class="bg-gray-700 border border-gray-700 rounded px-3 py-2 text-sm text-gray-500 placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-gray-500" phx-debounce="300" />
  <div id="tag-combobox" class="relative w-56 sm:w-64" phx-click-away="tags_close">
  <button type="button" phx-click="tags_toggle" class="w-full bg-gray-700 border border-gray-700 rounded px-3 py-2 text-sm text-gray-500 text-left focus:outline-none focus:ring-1 focus:ring-gray-500">
  <%= selected_tag_label(@tags, @selected_tag, @tag_index_pad) %>
  </button>
  <%= if @tags_open do %>
  <ul class="absolute z-10 mt-1 w-full max-h-64 overflow-auto bg-gray-700 border border-gray-700 rounded shadow-lg py-1">
  <li>
  <button type="button" phx-click="select_tag" phx-value-id="" class={tag_option_class(@selected_tag == "")}>All tags</button>
  </li>
  <%= for t <- @tags do %>
  <% id = to_string(t["uuid"] || t["key"] || t["id"]) %>
  <li>
  <button type="button" phx-click="select_tag" phx-value-id={id} class={tag_option_class(@selected_tag == id)}>
  <span class="inline-flex w-10 sm:w-12 shrink-0 justify-end pr-2 tabular-nums">
  <%= if is_integer(t["index"]) do %><%= t["index"] %><% end %>
  </span>
  <span class="inline-flex">—</span>
  <span class="inline-flex pl-2 min-w-0"> <%= t["name"] %> </span>
  </button>
  </li>
  <% end %>
  </ul>
  <% end %>
  </div>
  </form>

  <ul class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-9">
  <%= for ch <- @filtered_channels do %>
  <li class="flex items-center gap-3 px-2 py-2 rounded">
  <%= if ch["number"] do %>
  <span class="w-20 sm:w-24 shrink-0 text-gray-400 tabular-nums text-right"><%= ch["number"] %></span>
  <% else %>
  <span class="w-20 sm:w-24 shrink-0"></span>
  <% end %>
  <div class="w-24 h-12 rounded p-1 flex items-center justify-center shrink-0">
  <a href={stream_url(ch["uuid"], ch["name"])} target="_blank" rel="noopener noreferrer">
  <img class="max-h-full max-w-full object-contain" alt={ch["name"]}
  src={"/icons/#{encode_uri(ch["name"]) }.png"} />
  </a>
  </div>
  <div class="min-w-0 truncate">
  <%= ch["name"] %>
  </div>
  </li>
  <% end %>
  <%= if @filtered_channels == [] do %>
  <li class="px-2 py-2 text-sm text-gray-400">No channels found</li>
  <% end %>
  </ul>
  </div>
  """
  end

  def encode_uri(channel) do
    :uri_string.quote(channel)
  end

  def stream_url(channel_uuid, channel_name) do
    host = Application.get_env(:tvhstats, :tvh_host)
    port = Application.get_env(:tvhstats, :tvh_port)
    schema = if Application.get_env(:tvhstats, :tvh_use_https), do: "https", else: "http"
    encoded_title = URI.encode(channel_name)

    "#{schema}://#{host}:#{port}/play/ticket/stream/channel/#{channel_uuid}?title=#{encoded_title}"
  end

  # Formats the dropdown label as padded_index — name, ensuring the dash column aligns.
  defp format_tag_label(%{"name" => name} = t, pad_width) do
    idx = t["index"]
    case zero_pad_index(idx, pad_width) do
      nil -> name
      padded -> padded <> " — " <> name
    end
  end

  defp zero_pad_index(nil, _), do: nil
  defp zero_pad_index(idx, pad_width) when is_integer(idx) and pad_width > 0 do
    Integer.to_string(idx) |> String.pad_leading(pad_width, "0")
  end
  defp zero_pad_index(idx, _), do: Integer.to_string(idx)

  # Dropdown behavior helpers
  defp tag_option_class(selected?) do
    base = "w-full text-left px-3 py-4.5 text-sm text-gray-100 hover:bg-gray-700 flex items-center"
    if selected?, do: base <> " bg-gray-700", else: base
  end

  defp selected_tag_label(tags, selected_tag, pad_width) do
    cond do
      selected_tag == "" or is_nil(selected_tag) -> "All tags"
      true ->
        case Enum.find(tags, fn t -> to_string(t["uuid"] || t["key"] || t["id"]) == to_string(selected_tag) end) do
          nil -> "All tags"
          t -> format_tag_label(t, pad_width)
        end
    end
  end
end
