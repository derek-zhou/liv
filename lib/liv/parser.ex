defmodule Liv.Parser do
  use Md.Parser

  alias Md.Parser.Syntax.Void

  @default_syntax Map.put(Void.syntax(), :settings, Void.settings())

  @syntax @default_syntax
          |> Map.merge(%{
            substitute: [
              {"<", %{text: "&lt;"}},
              {"&", %{text: "&amp;"}}
            ],
            escape: [
              {<<92>>, %{}}
            ],
            comment: [
              {"<!--", %{closing: "-->"}}
            ],
            flush: [
              {"---", %{tag: :hr, rewind: :flip_flop}},
              {"  \n", %{tag: :br}},
              {"  \n", %{tag: :br}}
            ],
            block: [
              {"```", %{tag: [:pre, :code], pop: %{code: :class}}}
            ],
            shift: [
              {"    ", %{tag: [:div, :code], attributes: %{class: "pre"}}}
            ],
            pair: [
              {"![",
               %{
                 tag: :img,
                 closing: "]",
                 inner_opening: "(",
                 inner_closing: ")",
                 outer: {:attribute, {:src, :title}}
               }},
              {"!![",
               %{
                 tag: :figure,
                 closing: "]",
                 inner_opening: "(",
                 inner_closing: ")",
                 inner_tag: :img,
                 outer: {:tag, {:figcaption, :src}}
               }},
              {"?[",
               %{
                 tag: :abbr,
                 closing: "]",
                 inner_opening: "(",
                 inner_closing: ")",
                 outer: {:attribute, :title}
               }},
              {"[",
               %{
                 tag: :a,
                 closing: "]",
                 inner_opening: "(",
                 inner_closing: ")",
                 disclosure_opening: "[",
                 disclosure_closing: "]",
                 outer: {:attribute, :href}
               }}
            ],
            paragraph: [
              {"#", %{tag: :h1}},
              {"##", %{tag: :h2}},
              {"###", %{tag: :h3}},
              {"####", %{tag: :h4}},
              {"#####", %{tag: :h5}},
              {"######", %{tag: :h6}},
              # nested
              {">", %{tag: [:blockquote, :p]}}
            ],
            list:
              [
                {"- ", %{tag: :li, outer: :ul}},
                {"* ", %{tag: :li, outer: :ul}},
                {"+ ", %{tag: :li, outer: :ul}}
              ] ++ Enum.map(0..9, &{"#{&1}. ", %{tag: :li, outer: :ol}}),
            brace: [
              {"*", %{tag: :b}},
              {"_", %{tag: :i}},
              {"**", %{tag: :strong, attributes: %{class: "red"}}},
              {"__", %{tag: :em}},
              {"~", %{tag: :s}},
              {"~~", %{tag: :del}},
              {"``", %{tag: :span, mode: :raw, attributes: %{class: "code-inline"}}},
              {"`", %{tag: :code, mode: :raw, attributes: %{class: "code-inline"}}},
              {"[^", %{closing: "]", tag: :b, mode: :raw}}
            ]
          })
end
