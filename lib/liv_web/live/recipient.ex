defmodule LivWeb.Recipient do
  use Surface.Component

  alias Surface.Components.Form.{TextInput, Select}

  prop index, :integer, required: true
  prop type, :atom, required: true
  prop addr, :string, default: ""
  prop options, :list, default: []

  defp addr_string([nil | addr]), do: addr
  defp addr_string([name | addr]), do: "#{name} <#{addr}>"
end
