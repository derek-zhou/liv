defmodule LivWeb.Draft do
  alias Liv.DraftServer
  use Surface.Component

  prop text, :string, default: ""

  defp html_draft(text) do
    case DraftServer.html(text) do
      {:ok, html} -> html
      {:error, _e} -> "Illegal Markdown syntax"
    end
  end
end
