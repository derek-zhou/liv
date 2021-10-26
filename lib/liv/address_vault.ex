defmodule Liv.AddressVault do
  @moduledoc """
  I keep track of addresses used in the system
  """

  use GenServer
  require Logger
  alias Liv.Configer
  alias Phoenix.PubSub
  alias :self_configer, as: SelfConfiger

  defstruct [:subject, :recipients, :body, dirty: false, addr_to_name: %{}]

  @doc """
  add an email address to the database
  """
  def add(name, addr) do
    GenServer.cast(__MODULE__, {:add, name, addr})
  end

  @doc """
  return a list of email addresses that contains the string
  """
  def start_with(str) do
    GenServer.call(__MODULE__, {:start_with, str})
  end

  @doc """
  get draft
  """
  def get_draft() do
    GenServer.call(__MODULE__, :get_draft)
  end

  @doc """
  get the body text as a pasteboard
  """
  def get_pasteboard() do
    {_, _, body} = GenServer.call(__MODULE__, :get_draft)
    body
  end

  @doc """
  put the draft
  """
  def put_draft(subject, recipients, body) do
    # broadcast the event
    PubSub.local_broadcast_from(
      Liv.PubSub,
      self(),
      "messages",
      {:draft_update, subject, recipients, body}
    )

    GenServer.cast(__MODULE__, {:put_draft, subject, recipients, body})
  end

  @doc """
  clear the draft
  """
  def clear_draft(), do: put_draft(nil, nil, nil)

  @doc """
  put the text into the body of draft
  """
  def put_pasteboard(text), do: put_draft(nil, nil, text)

  @doc false
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)

    addr_to_name =
      :saved_addresses
      |> Configer.default()
      |> Enum.map(fn [name | addr] -> {addr, name} end)
      |> Enum.into(%{})

    {:ok, %__MODULE__{addr_to_name: addr_to_name}}
  end

  @impl true
  def terminate(_, %__MODULE__{dirty: false}), do: :ok

  def terminate(_, %__MODULE__{addr_to_name: addr_to_name}) do
    SelfConfiger.set_env(
      Configer,
      :saved_addresses,
      Enum.map(addr_to_name, fn {addr, name} -> [name | addr] end)
    )

    :ok
  end

  @impl true
  def handle_cast(
        {:add, name, addr},
        %__MODULE__{addr_to_name: addr_to_name} = state
      ) do
    {
      :noreply,
      %{state | dirty: true, addr_to_name: Map.put(addr_to_name, addr, name)},
      5000
    }
  end

  @impl true
  def handle_cast({:put_draft, subject, recipients, body}, state) do
    {:noreply, %{state | subject: subject, recipients: recipients, body: body}}
  end

  @impl true
  def handle_info(:timeout, %__MODULE__{dirty: false} = state) do
    {:noreply, state}
  end

  def handle_info(:timeout, %__MODULE__{addr_to_name: addr_to_name} = state) do
    SelfConfiger.set_env(
      Configer,
      :saved_addresses,
      Enum.map(addr_to_name, fn {addr, name} -> [name | addr] end)
    )

    {:noreply, %{state | dirty: false}}
  end

  @impl true
  def handle_call({:start_with, str}, _from, %__MODULE__{addr_to_name: addr_to_name} = state) do
    list =
      addr_to_name
      |> Enum.map(fn {addr, name} -> [name | addr] end)
      |> Enum.filter(fn [name | addr] ->
        cond do
          String.starts_with?(addr, str) -> true
          name == nil -> false
          String.starts_with?(name, str) -> true
          true -> false
        end
      end)

    {:reply, list, state}
  end

  @impl true
  def handle_call(
        :get_draft,
        _from,
        %__MODULE__{subject: subject, recipients: recipients, body: body} = state
      ) do
    {:reply, {subject, recipients, body}, state}
  end
end
