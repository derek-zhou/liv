defmodule LivWeb.MailNode do
  use Surface.Component

  alias LivWeb.Router.Helpers, as: Routes
  alias Surface.Components.LivePatch

  prop meta, :map, required: true
  prop tz_offset, :integer, default: 0
  prop docid, :integer, required: true
  
  defp unread?(flags), do: !Enum.member?(flags, :seen)

  defp email_name([nil | addr]), do: addr
  defp email_name([name | _addr]), do: name

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
