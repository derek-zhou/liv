defmodule LivWeb.Welcome do
  use Surface.LiveView
  require Logger
  alias LivWeb.Router.Helpers, as: Routes
  alias LivWeb.Login
  alias LivWeb.Main
  
  data auth, :atom, default: nil

  def mount(_params, _session, socket) do
    cond do
      !connected?(socket) -> {:ok, socket}
      true ->
	case socket.assigns do
	  %{auth: :ok} -> {:ok, socket}
	  _ ->
	    {:ok, push_event(socket, "get_value", %{key: "token"})}
	end
    end
  end

  def handle_event("get_value", %{"token" => token}, socket) do
    case token do
      "secret" ->
	{:noreply, assign(socket, :auth, :ok)}
      _ ->
	{
	  :noreply,
	  push_redirect(socket, to: Routes.live_path(socket, Login))
	}
    end
  end

end
