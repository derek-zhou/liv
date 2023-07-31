defmodule LivWeb.Write do
  use Surface.Component

  alias LivWeb.{Recipient, Draft}
  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, TextInput, TextArea, Label, Checkbox}

  prop change, :event, required: true
  prop submit, :event, required: true
  prop auto_recover, :event, required: true
  prop subject, :string, default: ""
  prop recipients, :list, default: []
  prop text, :string, default: ""
  prop addr_options, :list, default: []
  prop update_preview, :boolean, default: true

  defp email_addr(nil, addr), do: addr
  defp email_addr(name, addr), do: "#{name} <#{addr}>"

  defp text_debounce(true), do: "300"
  defp text_debounce(false), do: "blur"

  defp ui_recs(recs), do: recs ++ [{nil, [nil | ""]}]
end
