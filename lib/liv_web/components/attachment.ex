defmodule LivWeb.Attachment do
  use Surface.Component

  prop name, :string, required: true
  prop size, :integer, required: true
  prop offset, :integer, required: true
  prop url, :string, default: ""

  defp percentage(_offset, 0), do: 100
  defp percentage(offset, size), do: floor(offset / size * 100)
end
