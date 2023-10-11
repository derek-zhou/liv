defmodule Liv.Orbit do
  @moduledoc """
  The Orbit gen server
  """

  alias LivWeb.Endpoint
  alias LivWeb.Router.Helpers, as: Routes
  alias Phoenix.PubSub
  alias Liv.Configer

  require Logger
  use GenServer

  # client

  @doc false
  def start_link(default) when is_list(default) do
    GenServer.start_link(__MODULE__, default, name: __MODULE__)
  end

  # server
  @impl true
  def init(_) do
    PubSub.subscribe(Liv.PubSub, "messages")
    {:ok, []}
  end

  @impl true
  def handle_info({:mark_message, docid, mail}, state) do
    case {Configer.default(:orbit_api_key), Configer.default(:orbit_workspace)} do
      {"", _} -> :ok
      {_, ""} -> :ok
      {api_key, workspace} -> mark_orbit(docid, mail, api_key, workspace)
    end

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp mark_orbit(docid, mail, api_key, workspace) do
    key = to_string(docid)
    url = Routes.mail_url(Endpoint, :view, key)
    [_name | from] = mail.from

    date =
      ~U[1970-01-01 00:00:00Z]
      |> DateTime.add(mail.date)
      |> DateTime.to_iso8601()

    json_api_post(
      "https://app.orbit.love/api/v1/#{workspace}/activities",
      %{
        "title" => "new mail",
        "description" => mail.subject,
        "link" => url,
        "link_text" => "mail",
        "key" => key,
        "activity_type" => "post:created",
        "occurred_at" => date,
        "identity" => %{
          "source" => "email",
          "email" => from
        }
      },
      api_key,
      1000
    )
  end

  defp json_api_post(url, data, api_key, timeout) do
    case HTTPoison.post(url, Jason.encode!(data), [
           {"Accept", "application/json"},
           {"Authorization", "Bearer #{api_key}"},
           {"Content-Type", "application/json"}
         ]) do
      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.notice("api call to #{url} timeout. Will retry")
        json_api_post(url, data, api_key, next_timeout(timeout))

      {:error, %HTTPoison.Error{reason: reason}} ->
        raise("api call to #{url} failed: #{reason}")

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.notice("api call to #{url} busy. Will retry")
        json_api_post(url, data, api_key, next_timeout(timeout))

      {:ok, %HTTPoison.Response{status_code: code}} when code < 300 ->
        Logger.debug("api call to #{url} succeeded with response code: #{code}")
        :ok

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.warning("api call #{inspect(data)} failed with response code: #{code}")
        Logger.warning("response #{inspect(Jason.decode!(body))}")
        :ok
    end
  end

  defp next_timeout(timeout) when timeout < 1_000_000 do
    Process.sleep(timeout)
    timeout * 2
  end

  defp next_timeout(_timeout) do
    Process.sleep(1_000_000)
    1_000_000
  end
end
