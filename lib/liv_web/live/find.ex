defmodule LivWeb.Find do
  use Surface.Component
  alias Liv.MailClient
  alias LivWeb.MailNode

  prop mail_client, :map, required: true
  prop root, :integer
  prop tz_offset, :integer, default: 0
end
