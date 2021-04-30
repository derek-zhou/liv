defmodule LivWeb.Main do
  use Surface.Component
  alias LivWeb.Button

  slot default, required: true
  prop messages, :map, default: %{}
  prop title, :string, default: ""
  prop info, :string, default: ""
  prop buttons, :list, default: []
  
  defp alert_class("error"), do: "alert-danger"
  defp alert_class("warning"), do: "alert-warning"
  defp alert_class("info"), do: "alert-info"

end
