defmodule LivWeb.Find do
  use Surface.Component
  alias Liv.MailClient
  alias LivWeb.MailNode

  prop tree, :tuple, required: true
  prop mails, :map, required: true
  prop root, :integer
  prop tz_offset, :integer, default: 0
end
