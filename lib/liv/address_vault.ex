defmodule Liv.Correspondent do
  use Memento.Table, attributes: [:addr, :name, :mails]
end

defmodule Liv.AddressVault do
  @moduledoc """
  I keep track of addresses used in the system
  """

  require Logger
  alias Liv.{Configer, Correspondent}

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
