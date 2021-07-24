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
    PubSub.subscribe(Liv.PubSub, "mark_message")
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

  defp mark_orbit(docid, mail, api_key, workspace) do
    key = to_string(docid)
    url = Routes.mail_url(Endpoint, :view, key)
    date = NaiveDateTime.add(~N[1970-01-01 00:00:00], mail.date)

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
          "email" => elem(mail.from, 1)
        }
      },
      api_key
    )
  end

  defp json_api_post(url, data, api_key) do
    case HTTPoison.post(url, Jason.encode!(data), [
           {"Accept", "application/json"},
           {"Authorization", "Bearer #{api_key}"},
           {"Content-Type", "application/json"}
         ]) do
      {:error, %HTTPoison.Error{reason: reason}} ->
        raise("api call to #{url} failed: #{reason}")

      {:ok, %HTTPoison.Response{status_code: code}} when code < 300 ->
        Logger.debug("api call to #{url} succeeded with response code: #{code}")
        :ok

      {:ok, %HTTPoison.Response{status_code: code}} ->
        raise("api call to #{url} failed with response code: #{code}")
    end
  end
end
