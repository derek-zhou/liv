defmodule Liv.Message do
  @moduledoc """
  parse composed message
  """

  @doc """
  parse user input into a message
  """
  def parse(str) do
    ast =
      case EarmarkParser.as_ast(str) do
        {:ok, ast, _} -> ast
        {:error, ast, _} -> ast
      end

    ast
    |> Earmark.Transform.map_ast(&sanitize/1, true)
    |> Earmark.Transform.transform()
  end

  defp sanitize({tag, attrs, ast, _meta}) do
    {sanitize_tag(tag), Enum.flat_map(attrs, &sanitize_attr/1), ast, %{}}
  end

  # this is the list of sanctioned tags
  [
    "a",
    "b",
    "blockquote",
    "br",
    "code",
    "dd",
    "del",
    "div",
    "dl",
    "dt",
    "em",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "hr",
    "i",
    "img",
    "li",
    "ol",
    "p",
    "pre",
    "q",
    "small",
    "span",
    "strong",
    "sub",
    "sup",
    "table",
    "tbody",
    "td",
    "tfoot",
    "th",
    "thead",
    "tr",
    "u",
    "ul"
  ]
  |> Enum.each(fn tag ->
    defp sanitize_tag(unquote(tag)), do: unquote(tag)
  end)

  # all other tags are replaced with div
  defp sanitize_tag(_), do: "div"

  # we only allow a few attributes
  # alt for accessibility
  defp sanitize_attr({"alt", value}), do: [{"alt", value}]
  # absolute links
  defp sanitize_attr({"href", <<"http", _rest::binary>> = value}), do: [{"href", value}]
  # absolute assets
  defp sanitize_attr({"src", <<"http", _rest::binary>> = value}), do: [{"src", value}]
  # everything else are droped
  defp sanitize_attr({_name, _value}), do: []
end
