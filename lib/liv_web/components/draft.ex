defmodule LivWeb.Draft do
  alias Liv.DraftServer
  use Surface.Component

  prop text, :string, default: ""

  defp html_draft(text), do: DraftServer.html(text)
end
