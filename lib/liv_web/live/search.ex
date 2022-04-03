defmodule LivWeb.Search do
  use Surface.Component

  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, Label, TextInput}

  prop default_query, :string, required: true
  prop submit, :event, required: true
  prop pick_example, :string, required: true

  prop examples, :list,
    default: [
      {"The Inbox", "maildir:/"},
      {"Unread mails", "flag:unread"},
      {"Last 7 days", "date:7d..now"}
    ]
end
