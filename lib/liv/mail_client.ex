defmodule Liv.MailClient do
  @moduledoc """
  The core MailClient state mamangment abstracted from the UI. 
  """
  alias :maildir_commander, as: MaildirCommander
  alias :mc_tree, as: MCTree
  alias :mc_mender, as: MCMender

  defstruct [
    :tree, :mails
  ]

  @doc """
  run a query. query can be a query string or a docid integer
  """
  def new_search(query) do
    case MaildirCommander.find(query, true, :":date", true) do
      {:error, msg} -> raise(msg)
      {:ok, tree, mails} ->
	%__MODULE__{tree: MCTree.collapse(tree), mails: mails}
    end
  end

  @doc """
  mark a message seen. if the mc is nil, make a minimum mc first
  """
  def seen(nil, docid) do
    docid
    |> new_search()
    |> seen(docid)
  end

  def seen(%__MODULE__{mails: mails} = mc, docid) do
    case Map.get(mails, docid) do
      nil -> mc
      %{flags: flags} = headers ->
	case Enum.member?(flags, :seen) do
	  true -> mc
	  false ->
	    headers = %{headers | flags: [:seen | flags]}
	    %{mc | docid => headers}
	end
    end
  end	

  @doc """
  getter of a specific mail metadata
  """
  def mail_meta(%__MODULE__{mails: mails}, docid), do: Map.get(mails, docid)

  @doc """
  getter of the mail content
  """
  def mail_content(%__MODULE__{mails: mails}, docid) do
    case Map.get(mails, docid) do
      %{path: path} -> MCMender.fetch_mime(path)
      _ -> {:error, "No mail of this id: #{docid} found"}
    end
  end

  @doc """
  getter of mail counts
  """
  def mail_count(%__MODULE__{tree: tree}) do
    MCTree.traverse(fn _ -> :ok end, tree)
  end

  @doc """
  getter of unread mail counts
  """
  def unread_count(%__MODULE__{tree: tree, mails: mails}) do
    MCTree.traverse(fn docid ->
      case Map.get(mails, docid) do
	%{flags: flags} ->
	  case Enum.member?(flags, :seen) do
	    true -> nil
	    false -> :ok
	  end
	_ -> nil
      end
    end, tree)
  end

  @doc """
  test if a docid is in the client
  """
  def contains?(%__MODULE__{mails: mails}, docid) do
    Map.has_key?(mails, docid)
  end
  
  @doc """
  getter of the next docid
  """
  def next(%__MODULE__{tree: tree}, docid) do
    case MCTree.next(docid, tree) do
      :undefined -> nil
      id -> id
    end
  end

  @doc """
  getter of the previous docid
  """
  def previous(%__MODULE__{tree: tree}, docid) do
    case MCTree.prev(docid, tree) do
      :undefined -> nil
      id -> id
    end
  end

  @doc """
  getter of all children of docid. pass nil get the root list
  """
  def children_of(%__MODULE__{tree: tree}, docid) do
    MCTree.children(docid || :undefined, tree) 
  end

end

