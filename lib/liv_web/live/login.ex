defmodule LivWeb.Login do
  use Surface.LiveView
  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, Label, PasswordInput}
  alias LivWeb.Router.Helpers, as: Routes
  alias LivWeb.Main
  alias LivWeb.Welcome
  
  def handle_event("submit", %{"login" => %{"passcode" => passcode}},
    socket) do
    cond do
      check_passcode?(passcode) ->
	{
	  :noreply,
	  socket
	  |> push_event("set_value", %{key: "token", value: passcode})
	  |> push_event("redirect",
	    %{href: Routes.live_path(socket, Welcome)}) 
	}
      true ->
	{:noreply, put_flash(socket, :error, "Login failed")}
    end
  end

  defp check_passcode?("secret"), do: true
  defp check_passcode?(_), do: false

end
