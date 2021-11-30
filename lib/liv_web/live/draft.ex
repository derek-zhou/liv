defmodule LivWeb.Draft do
  alias Liv.Message
  use Surface.Component

  prop text, :string, default: ""
end
