defmodule LivWeb.Attachment do
  use Surface.Component

  prop name, :string, required: true
  prop size, :integer, required: true
  prop offset, :integer, required: true
  prop url, :string, default: ""
end
