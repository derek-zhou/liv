defmodule Liv.DraftServer do
  use GenServer
  alias Phoenix.PubSub
  alias :bbmustache, as: BBMustache
  alias Liv.{Sanitizer, Message}
  alias HtmlSanitizeEx.Scrubber

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

  @doc """
  return the text of the draft, draft can be html or markdown, depends on the first char
  for html draft, there is no text. for markdown draft, the text is markdown itself
  """
  def text(<<"<", _::binary>>), do: ""
  def text(t), do: t

  @doc """
  return the html of the draft, draft can be html or markdown, depends on the first char.
  Second argument is optional, a map of variable substitution in case of html draft
  html draft is a mustache template, to be render with the map
  markdown draft is converted to html straight
  """
  def html(draft, map \\ %{})
  def html(<<"<", _::binary>> = draft, map), do: BBMustache.render(draft, map, key_type: :atom)
  def html(draft, _map), do: Earmark.as_html!(draft)

  @doc """
  return a version html that is safe to be embedded in our page.
  """
  def safe_html(<<"<", _::binary>> = draft), do: Scrubber.scrub(draft, Sanitizer)
  def safe_html(draft), do: Message.parse(draft)

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
