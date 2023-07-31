defmodule LivWeb.Config do
  use Surface.Component

  alias LivWeb.RemoteMailBox
  alias Surface.Components.Form

  alias Surface.Components.Form.{
    Field,
    TextInput,
    NumberInput,
    PasswordInput,
    Select,
    Label,
    TextArea
  }

  prop change, :event, required: true
  prop submit, :event, required: true
  prop my_addr, :list, required: true
  prop my_addrs, :list, required: true
  prop my_lists, :list, required: true
  prop days, :integer, required: true
  prop maildir, :string, required: true
  prop orbit_api_key, :string, required: true
  prop orbit_workspace, :string, required: true
  prop sending_method, :atom, required: true
  prop sending_data, :map, required: true
  prop reset_password, :string, default: ""
  prop remote_mail_boxes, :list, default: []

  defp ui_boxes(boxes) do
    boxes ++ [%{method: "", username: "", password: "", hostname: ""}]
  end

  defp field_class(true), do: "field"
  defp field_class(false), do: "hide"
end
