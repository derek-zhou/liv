defmodule LivWeb.Attachment do
  use Surface.Component

  prop seq, :integer, required: true
  prop name, :string, required: true
  prop size, :integer, required: true
  prop offset, :integer, required: true
  prop type, :string, required: true
  prop url, :string, default: ""

  defp percentage(_offset, 0), do: 100
  defp percentage(offset, size), do: floor(offset / size * 100)

  defp display_name("", "text/plain"), do: "mail.txt"
  defp display_name("", "text/html"), do: "mail.html"
  defp display_name(name, _), do: name
end
