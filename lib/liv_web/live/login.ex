defmodule LivWeb.Login do
  use Surface.Component

  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, Label, PasswordInput}

  prop prompt, :string, required: true
  prop submit, :event, required: true
end
