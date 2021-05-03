defmodule LivWeb.Config do
  use Surface.Component

  alias LivWeb.Router.Helpers, as: Routes
  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, TextInput, Label, TextArea}
  alias Surface.Components.LivePatch

  prop change, :event, required: true
  prop my_addr, :list, required: true
  prop my_addrs, :list, required: true
  prop my_lists, :list, required: true

end
