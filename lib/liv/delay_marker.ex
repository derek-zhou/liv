defmodule Liv.DelayMarker do
  use GenServer

  require Logger

  alias :maildir_commander, as: MaildirCommander
  alias Phoenix.PubSub

  @poll_interval 3_600_000

  @doc false
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  mark a message of this flag at some time later.
  The default flag is -S, which will make the message unread again
  """
  def flag(docid, seconds, flag \\ "-S") do
    now = System.convert_time_unit(System.monotonic_time(), :native, :second)
    GenServer.cast(__MODULE__, {:flag, docid, now + seconds, flag})
  end

  @doc ~S"""
  ping the server so all cast finished
  """
  def ping() do
    GenServer.call(__MODULE__, :ping)
  end

  defp flag_it(docid, flag) do
    case MaildirCommander.flag(docid, flag) do
      {:ok, m} ->
        # broadcast the event
        PubSub.local_broadcast(Liv.PubSub, "messages", {:seen_message, docid, m})

      {:error, msg} ->
        Logger.warning("docid: #{docid} #{msg}")
    end
  end

  @impl true
  def init(_) do
    Process.send_after(self(), :poll, @poll_interval)
    {:ok, []}
  end

  @impl true
  def terminate(_reason, queue) do
    # flag everthing regardless time
    Enum.each(queue, fn {docid, _at, flag} -> flag_it(docid, flag) end)
  end

  @impl true
  def handle_cast({:flag, docid, at, flag}, queue) do
    {:noreply, insert_queue(queue, docid, at, flag)}
  end

  @impl true
  def handle_call(:ping, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:poll, []) do
    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, []}
  end

  @impl true
  def handle_info(:poll, [{docid, at, flag} | tail] = queue) do
    now = System.convert_time_unit(System.monotonic_time(), :native, :second)

    cond do
      at < now ->
        flag_it(docid, flag)
        send(self(), :poll)
        {:noreply, tail}

      true ->
        limit = (at + 1 - now) * 1000
        limit = if limit > @poll_interval, do: @poll_interval, else: limit
        Process.send_after(self(), :poll, limit)
        {:noreply, queue}
    end
  end

  defp insert_queue([], docid, at, flag), do: [{docid, at, flag}]

  defp insert_queue([{_, h_at, _} = head | tail], docid, at, flag) do
    cond do
      h_at < at -> [head | insert_queue(tail, docid, at, flag)]
      true -> [{docid, at, flag}, head | tail]
    end
  end
end
