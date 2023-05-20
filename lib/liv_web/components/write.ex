defmodule LivWeb.Write do
  use Surface.Component

  alias LivWeb.{Recipient, Draft}
  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, TextInput, TextArea}

  prop change, :event, required: true
  prop submit, :event, required: true
  prop auto_recover, :event, required: true
  prop debounce, :integer, default: 1000
  prop subject, :string, default: ""
  prop recipients, :list, default: []
  prop text, :string, default: ""
  prop addr_options, :list, default: []

  defp email_addr(nil, addr), do: addr
  defp email_addr(name, addr), do: "#{name} <#{addr}>"

  defp ui_recs(recs), do: recs ++ [{nil, [nil | ""]}]
end
