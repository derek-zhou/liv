defmodule LivWeb.Recipient do
  use Surface.Component

  alias Surface.Components.Form.{TextInput, Select}

  prop index, :integer, required: true
  prop type, :atom, required: true
  prop addr, :string, default: ""

end
