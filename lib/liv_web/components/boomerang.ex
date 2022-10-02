defmodule LivWeb.Boomerang do
  use Surface.Component

  alias Surface.Components.Form

  alias Surface.Components.Form.{
    Field,
    Label,
    RadioButton
  }

  prop submit, :event, required: true
end
