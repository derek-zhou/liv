defmodule Liv.Configer do
  @app :liv

  def default(:my_address), do: default_value(:my_address, [nil | "you@example.com"])
  def default(:my_addresses), do: default_value(:my_addresses, ["you@example.com"])
  def default(:my_email_lists), do: default_value(:my_email_lists, [])
  def default(:saved_addresses), do: default_value(:saved_addresses, [])
  def default(:archive_days), do: default_value(:archive_days, 30)
  def default(:archive_maildir), do: default_value(:archive_maildir, "/.Archive")
  def default(:orbit_api_key), do: default_value(:orbit_api_key, "")
  def default(:orbit_workspace), do: default_value(:orbit_workspace, "")

  defp default_value(key, default), do: Application.get_env(@app, key, default)
end
