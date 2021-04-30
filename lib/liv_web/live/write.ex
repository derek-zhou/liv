defmodule LivWeb.Write do
  use Surface.Component

  alias LivWeb.Recipient
  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, TextInput, TextArea}

  prop submit, :event, required: true
  prop change, :event, required: true
  prop subject, :string, default: ""
  prop recipients, :list, default: []
  prop mail_text, :string, default: ""
  prop addr_options, :list, default: []

  defp email_addr(nil, addr), do: addr
  defp email_addr(name, addr), do: "#{name} <#{addr}>"

  defp preview(text) do
    try do
      Earmark.as_html!(text)
    rescue
      RuntimeError ->
	"""
	<div class="alert alert-danger">Ilegal markdown</div>
	"""
    end
  end

end
