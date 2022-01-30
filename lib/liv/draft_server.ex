defmodule Liv.DraftServer do
  use GenServer
  alias Phoenix.PubSub

  defstruct [:subject, :recipients, :body]

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
    body || ""
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
  def put_pasteboard(subject, text), do: put_draft(subject, nil, text)

  @doc false
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:put_draft, subject, recipients, body}, state) do
    {:noreply, %{state | subject: subject, recipients: recipients, body: body}}
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
