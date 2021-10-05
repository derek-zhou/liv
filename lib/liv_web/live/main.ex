defmodule LivWeb.Main do
  use Surface.Component
  alias LivWeb.Button
  alias LivWeb.Router.Helpers, as: Routes

  slot default, required: true
  prop messages, :map, default: %{}
  prop info, :string, default: ""
  prop buttons, :list, default: []

  defp alert_class("error"), do: "alert-danger"
  defp alert_class("warning"), do: "alert-warning"
  defp alert_class("info"), do: "alert-info"
end
