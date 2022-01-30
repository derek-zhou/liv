defmodule LivWeb.Draft do
  alias Liv.DraftServer
  use Surface.Component

  prop text, :string, default: ""

  defp html_draft(html), do: html |> DraftServer.safe_html() |> raw()
end
