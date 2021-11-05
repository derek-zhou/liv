defmodule LivWeb.View do
  use Surface.Component
  alias LivWeb.Router.Helpers, as: Routes
  alias LivWeb.Endpoint
  alias Surface.Components.LivePatch
  alias LivWeb.Attachment
  alias Liv.Sanitizer
  alias HtmlSanitizeEx.Scrubber

  @max_inline_html 4096

  prop meta, :map, required: true
  prop content, :tuple, default: {:text, ""}
  prop attachments, :list, default: []
  prop tz_offset, :integer, default: 0

  defp email_name([nil | addr]), do: addr
  defp email_name([name | _addr]), do: name

  defp date_string(datei, tz_offset) do
    ~N[1970-01-01 00:00:00]
    |> NaiveDateTime.add(datei)
    |> NaiveDateTime.add(0 - tz_offset * 60)
    |> NaiveDateTime.to_string()
  end

  defp flags_string(flags) do
    flags
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
  end

  defp is_plain_text?({:text, _}), do: true
  defp is_plain_text?({:html, _}), do: false

  defp oversized?({:text, _}), do: false
  defp oversized?({:html, html}), do: byte_size(html) >= @max_inline_html

  defp inlined?({:text, _}), do: false
  defp inlined?({:html, html}), do: byte_size(html) < @max_inline_html

  defp text_part({_, text}), do: html_escape(text)

  defp sanitize({_, html}), do: html |> Scrubber.scrub(Sanitizer) |> raw()
end
