defmodule Liv.Correspondent do
  use Memento.Table, attributes: [:addr, :name, :mails]
end

defmodule Liv.AddressBookEntry do
  defstruct addr: nil, name: nil, first: nil, last: nil, count: 0
end

defmodule Liv.AddressVault do
  @moduledoc """
  I keep track of addresses used in the system
  """

  require Logger
  alias Liv.{Configer, Correspondent, AddressBookEntry, MailClient}

  @doc """
  add an email address to the database
  """
  def add(name, addr) do
    Memento.transaction!(fn ->
      case Memento.Query.read(Correspondent, addr) do
        nil ->
          Memento.Query.write(%Correspondent{name: name, addr: addr, mails: []})

        _ ->
          :ok
      end
    end)

    :ok
  end

  @doc """
  return a list of email addresses that contains the string
  """
  def start_with(str) do
    list =
      Memento.transaction!(fn ->
        Memento.Query.all(Correspondent)
      end)

    list
    |> Enum.map(fn %Correspondent{addr: addr, name: name} -> [name | addr] end)
    |> Enum.filter(fn [name | addr] ->
      cond do
        String.starts_with?(addr, str) -> true
        name == nil -> false
        String.starts_with?(name, str) -> true
        true -> false
      end
    end)
  end

  @doc """
  return a list of correspondents from the address book
  """
  def all_entries() do
    my_addresses = MapSet.new(Configer.default(:my_addresses))

    Memento.transaction!(fn ->
      Memento.Query.all(Correspondent)
    end)
    |> Enum.filter(fn %Correspondent{mails: mails} -> !Enum.empty?(mails) end)
    |> Enum.reject(&MapSet.member?(my_addresses, &1.addr))
    |> Enum.map(fn %Correspondent{addr: addr, name: name, mails: mails} ->
      %AddressBookEntry{
        addr: addr,
        name: name,
        last: mails |> List.first() |> MailClient.date_of(),
        first: mails |> List.last() |> MailClient.date_of(),
        count: Enum.count(mails)
      }
    end)
  end

  @doc """
  mark a docid as from one address
  """
  def mark([_ | nil], _), do: :ok
  def mark([_ | ""], _), do: :ok

  def mark([name | addr], docid) do
    Memento.transaction!(fn ->
      case Memento.Query.read(Correspondent, addr) do
        nil ->
          Memento.Query.write(%Correspondent{name: name, addr: addr, mails: [docid]})

        %Correspondent{mails: mails} = c ->
          Memento.Query.write(%{c | mails: [docid | mails]})
      end
    end)

    :ok
  end

  @doc """
  undo the mark of a docid as from one address
  """
  def unmark([_ | nil], _), do: :ok
  def unmark([_ | ""], _), do: :ok

  def unmark([_ | addr], docid) do
    Memento.transaction!(fn ->
      case Memento.Query.read(Correspondent, addr) do
        nil ->
          :ok

        %Correspondent{mails: mails} = c ->
          Memento.Query.write(%{c | mails: Enum.reject(mails, &(&1 == docid))})
      end
    end)

    :ok
  end

  @doc """
  install mnesia in the node
  """
  def install!() do
    nodes = [node()]

    Memento.stop()
    Memento.Schema.create(nodes)
    Memento.start()
    Memento.Table.create!(Liv.Correspondent, disc_copies: nodes)
  end

  @doc """
  migrate old data from the configer
  """
  def migrate!() do
    table = Configer.default(:saved_addresses)

    Memento.Transaction.execute_sync!(fn ->
      Enum.each(table, fn [name | addr] ->
        Logger.info("Saving \"#{name}\" <#{addr}>")
        Memento.Query.write(%Correspondent{name: name, addr: addr, mails: []})
      end)
    end)
  end
end
