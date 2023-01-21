defmodule LivWeb.AddressBook do
  use Surface.Component

  alias LivWeb.Router.Helpers, as: Routes
  alias LivWeb.Endpoint
  alias Surface.Components.LivePatch

  prop book, :list, default: []
  prop sorted_by, :atom, default: :from
  prop desc, :boolean, default: false
  prop tz_offset, :integer, default: 0
  prop delete, :string, required: true

  defp from(nil, addr), do: addr
  defp from(name, _addr), do: name

  def query_for(addr), do: "from:#{addr} flag:replied"

  defp date_string(nil, _tz_offset), do: ""

  defp date_string(datei, tz_offset) do
    utc = NaiveDateTime.add(~N[1970-01-01 00:00:00], datei)
    now = NaiveDateTime.utc_now()
    local = NaiveDateTime.add(utc, 0 - tz_offset * 60)

    case NaiveDateTime.diff(now, utc) do
      diff when diff < 86400 ->
        local
        |> NaiveDateTime.to_time()
        |> Time.to_string()

      _ ->
        local
        |> NaiveDateTime.to_date()
        |> Date.to_string()
    end
  end
end
