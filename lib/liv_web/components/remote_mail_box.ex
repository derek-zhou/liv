defmodule LivWeb.RemoteMailBox do
  use Surface.Component
  alias Surface.Components.Form.{Field, Label, PasswordInput, TextInput, Select}

  prop index, :integer, required: true
  prop box, :map, required: true
end
