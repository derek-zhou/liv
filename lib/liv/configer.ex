defmodule Liv.Configer do
  @app :liv

  def default(:my_address), do: default_value(:my_address, [nil | "you@example.com"])
  def default(:my_addresses), do: default_value(:my_addresses, ["you@example.com"])
  def default(:my_email_lists), do: default_value(:my_email_lists, [])
  def default(:saved_addresses), do: default_value(:saved_addresses, [])

  defp default_value(key, default), do: Application.get_env(@app, key, default)
end
