defmodule Commanded.EventStore.Adapters.Extreme.SubscriptionsSupervisor do
  @moduledoc false

  use DynamicSupervisor

  require Logger

  alias Commanded.EventStore.Adapters.Extreme.Subscription

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, [], opts)
  end

  @impl DynamicSupervisor
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_subscription(
        adapter_name,
        stream,
        subscription_name,
        subscriber,
        serializer,
        opts,
        index \\ 0
      ) do
    name = name(adapter_name)

    spec =
      subscription_spec(
        adapter_name,
        stream,
        subscription_name,
        subscriber,
        serializer,
        opts,
        index
      )

    case DynamicSupervisor.start_child(name, spec) do
      {:ok, pid} ->
        {:ok, pid}

      {:ok, pid, _info} ->
        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        case Keyword.get(opts, :concurrency_limit) do
          nil ->
            {:error, :subscription_already_exists}

          concurrency_limit ->
            if index < concurrency_limit - 1 do
              start_subscription(
                adapter_name,
                stream,
                subscription_name,
                subscriber,
                serializer,
                opts,
                index + 1
              )
            else
              {:error, :too_many_subscribers}
            end
        end

      reply ->
        reply
    end
  end

  def stop_subscription(adapter_name, subscription) do
    name = name(adapter_name)

    DynamicSupervisor.terminate_child(name, subscription)
  end

  defp subscription_spec(
         adapter_name,
         stream,
         subscription_name,
         subscriber,
         serializer,
         opts,
         index
       ) do
    start_args = [
      adapter_name,
      stream,
      subscription_name,
      subscriber,
      serializer,
      Keyword.put(opts, :index, index)
    ]

    %{
      id: {Subscription, stream, subscription_name, index},
      start: {Subscription, :start_link, start_args},
      restart: :temporary,
      shutdown: 5_000,
      type: :worker
    }
  end

  defp name(adapter_name), do: Module.concat([adapter_name, __MODULE__])
end
