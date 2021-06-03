defmodule LivWeb.Write do
  use Surface.Component

  alias LivWeb.Recipient
  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, TextInput, FileInput, TextArea}

  prop change, :event, required: true
  prop drop, :event, required: true
  prop subject, :string, default: ""
  prop recipients, :list, default: []
  prop mail_text, :string, default: ""
  prop addr_options, :list, default: []
  prop current, :tuple, default: nil
  prop attachments, :list, default: []

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

  defp attachments_info(attachments) do
    {count, bytes} =
      Enum.reduce(attachments, {0, 0}, fn {_name, s, _data}, {c, b} -> {c + 1, b + s} end)

    "#{count} files, #{div(bytes, 1024)}KB"
  end

  defp progress_percent(nil), do: 0

  defp progress_percent({_name, size, offset, _data}) do
    floor(offset / size * 100)
  end
end
