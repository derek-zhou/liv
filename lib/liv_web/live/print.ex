defmodule LivWeb.Print do
  use Surface.Component

  prop content, :tuple, default: {:text, ""}

  defp is_plain_text?({:text, _}), do: true
  defp is_plain_text?({:html, _}), do: false

  defp text_part({:text, text}), do: html_escape(text)
  defp html_part({:html, html}), do: html
end
