defmodule LivWeb.ViewHeader do
  use Surface.Component
  alias LivWeb.Router.Helpers, as: Routes
  alias LivWeb.{Endpoint, Attachment}
  alias Surface.Components.LivePatch

  prop meta, :any, required: true
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
end
