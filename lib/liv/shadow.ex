defmodule Liv.Shadow do
  @moduledoc """
  a shadow server to store all assings on the side for backup
  """

  require Logger
  use GenServer, restart: :transient
  alias Liv.{ShadowSupervisor, Shadows}

  def child_spec(name) do
    %{id: name, start: {__MODULE__, :start_link, [name]}, restart: :transient}
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, nil, name: {:via, Registry, {Shadows, name}})
  end

  @doc """
  load the data from the shadow, create a shadow if one is missing.
  """
  def get(token) do
    case Registry.lookup(Shadows, token) do
      [{pid, _}] ->
        GenServer.call(pid, :get)

      _ ->
        start(token)
        %{}
    end
  end

  @doc """
  add assigns to the shadow, returns :ok
  """
  def assign(nil, _), do: :ok

  def assign(token, keyword) do
    GenServer.cast({:via, Registry, {Shadows, token}}, {:assign, keyword})
  end

  @doc """
  start the shadow server
  """
  def start(token) do
    DynamicSupervisor.start_child(ShadowSupervisor, {__MODULE__, token})
  end

  @doc """
  stop the shadow server
  """
  def stop(token), do: GenServer.cast({:via, Registry, {Shadows, token}}, :stop)

  # server
  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast({:assign, keyword}, state) do
    {:noreply, Enum.reduce(keyword, state, fn {k, v}, map -> Map.put(map, k, v) end)}
  end

  @impl true
  def handle_cast(:stop, state), do: {:stop, :normal, state}
end
