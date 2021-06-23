defmodule LivWeb.View do
  use Surface.Component
  alias LivWeb.Router.Helpers, as: Routes
  alias Surface.Components.LivePatch
  alias LivWeb.Attachment
  alias Liv.Sanitizer
  alias HtmlSanitizeEx.Scrubber

  @max_inline_html 4096

  prop meta, :map, required: true
  prop html, :string, default: ""
  prop text, :string, default: ""
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

  defp oversized?(html), do: byte_size(html) >= @max_inline_html

  defp inlined?(""), do: false
  defp inlined?(html), do: byte_size(html) < @max_inline_html

  defp sanitize(html), do: html |> Scrubber.scrub(Sanitizer) |> raw()
end
