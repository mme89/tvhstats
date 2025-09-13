defmodule TVHStats.Subscriptions do
  alias TVHStats.Repo
  alias TVHStats.Subscriptions.Query, as: SubscriptionQueries
  alias TVHStats.Subscriptions.Subscription

  @spec create(map) ::
          {:ok, Subscription.t()}
          | :ok
          | {:error, Ecto.Changeset.t()}
          | {:error, %{:errors => [map], subscription: nil}}
  def create(attrs \\ %{}) do
    query =
      attrs
      |> Map.get(:hash)
      |> SubscriptionQueries.get_by_hash()

    if Repo.exists?(query) do
      :ok
    else
      changeset = Subscription.changeset(%Subscription{}, attrs)
      {:ok, _subscription} = Repo.insert(changeset)
    end
  end

  @spec list() :: [Subscription.t()]
  def list(page \\ 1, size \\ 20) do
    query = SubscriptionQueries.get_paginated(page, size)

    Repo.all(query)
  end

  @spec list_with_filters(integer(), integer(), map()) :: [Subscription.t()]
  def list_with_filters(page \\ 1, size \\ 20, filters \\ %{}) do
    query = SubscriptionQueries.get_paginated_with_filters(page, size, filters)

    Repo.all(query)
  end

  def count() do
    query = SubscriptionQueries.get_count()

    Repo.one(query)
  end

  @spec count_with_filters(map()) :: integer()
  def count_with_filters(filters \\ %{}) do
    query = SubscriptionQueries.get_count_with_filters(filters)

    Repo.one(query)
  end

  def currently_playing() do
    query = SubscriptionQueries.get_playing()

    Repo.all(query)
  end

  def stop(subscription) do
    subscription
    |> Map.get(:hash)
    |> SubscriptionQueries.get_by_hash()
    |> Repo.one!()
    |> Subscription.update_changeset(%{stopped_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def stop_all(subscriptions) do
    subscriptions
    |> Enum.map(&Map.get(&1, :hash))
    |> SubscriptionQueries.stop_all()
    |> Repo.update_all([])
  end

  def remove_all_by_hash([]), do: :ok

  def remove_all_by_hash(subscriptions) do
    subscriptions
    |> SubscriptionQueries.list_by_hash()
    |> Repo.delete_all()
  end

  def get_plays_for_last_n(field, last_n_days) do
    field
    |> SubscriptionQueries.get_play_count(last_n_days)
    |> Repo.all()
  end

  def get_duration_for_last_n(field, last_n_days) do
    field
    |> SubscriptionQueries.get_play_duration(last_n_days)
    |> Repo.all()
    |> Enum.map(
      &Map.put(&1, "duration", &1["duration"] |> Decimal.round(0, :floor) |> Decimal.to_integer())
    )
  end

  def get_count_and_duration_for_last_n(field, last_n_days) do
    field
    |> SubscriptionQueries.get_play_count_and_duration(last_n_days)
    |> Repo.all()
    |> Enum.map(
      &Map.update!(&1, "duration", fn d -> d |> Decimal.round(0, :floor) |> Decimal.to_integer() end)
    )
  end

  def get_activity_for_last_n(last_n_days) do
    last_n_days
    |> SubscriptionQueries.get_play_activity()
    |> Repo.all()
  end

  def get_daily_plays(last_n_days) do
    last_n_days
    |> SubscriptionQueries.get_daily_activity()
    |> Repo.all()
  end

  def get_hourly_plays(last_n_days) do
    last_n_days
    |> SubscriptionQueries.get_hourly_activity()
    |> Repo.all()
  end

  def get_weekday_plays(last_n_days) do
    last_n_days
    |> SubscriptionQueries.get_weekday_activity()
    |> Repo.all()
  end

  @spec reset_all() :: {integer(), nil | [term()]}
  def reset_all() do
    Repo.delete_all(Subscription)
  end

  def get_top_channels(last_n_days \\ 30) do
    get_plays_for_last_n(:channel, last_n_days)
  end

  def get_top_users(last_n_days \\ 30) do
    get_plays_for_last_n(:user, last_n_days)
  end

  def get_stream_type_distribution(last_n_days \\ 30) do
    last_n_days
    |> SubscriptionQueries.get_stream_type_distribution()
    |> Repo.all()
    |> Enum.map(fn {type, count} -> %{type: type, count: count} end)
  end

  def get_channel_watch_time(last_n_days \\ 30) do
    get_duration_for_last_n(:channel, last_n_days)
  end

  def get_average_session_duration(last_n_days \\ 30) do
    result = last_n_days
    |> SubscriptionQueries.get_average_session_duration()
    |> Repo.one()

    case result do
      %{avg_duration: nil} -> 0
      %{avg_duration: avg} -> Decimal.to_float(avg) |> Float.round(0) |> trunc()
    end
  end
end
