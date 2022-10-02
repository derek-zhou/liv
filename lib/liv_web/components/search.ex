defmodule LivWeb.Search do
  use Surface.Component

  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, Label, TextInput}

  prop submit, :event, required: true
  prop pick_example, :string, required: true
  prop default_query, :string, required: true
  prop examples, :list, required: true
end
