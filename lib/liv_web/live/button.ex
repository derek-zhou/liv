defmodule LivWeb.Button do
  use Surface.Component
  alias Surface.Components.LivePatch

  prop text, :string, required: true
  prop type, :atom, required: true
  prop path_or_msg, :string, required: true
  prop disabled, :boolean, default: false
end
