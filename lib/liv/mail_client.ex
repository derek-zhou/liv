defmodule Liv.MailClient do
  @moduledoc """
  The core MailClient state mamangment abstracted from the UI. 
  """

  alias :maildir_commander, as: MaildirCommander
  alias :mc_tree, as: MCTree

  defstruct [
    :tree, :mails, :contents
  ]

  @doc """
  run a query. query can be a query string or a docid integer
  """
  def new_search(query) do
    case MaildirCommander.find(query, true, :":date", true,
	String.match?(query, ~r/^msgid:/)) do
      {:error, msg} -> raise(msg)
      {:ok, tree, mails} ->
	%__MODULE__{tree: MCTree.collapse(tree), mails: mails, contents: %{}}
    end
  end

  @doc """
  mark a message seen. if the mc is nil, make a minimum mc first
  """
  def seen(nil, docid) do
    case MaildirCommander.full_mail(docid) do
      {:error, msg} -> raise(msg)
      {meta, text, html} ->
	meta = case Enum.member?(meta.flags, :seen) do
	  true -> meta
	  false ->
	    MaildirCommander.flag(docid, "+S")
	    %{meta | flags: [:seen | Enum.reject(meta.flags, &(&1 == :unread))]}
	end
	%__MODULE__{ tree: MCTree.single(docid),
		     mails: %{docid => meta},
		     contents: %{docid => html_mail(text, html)} }
    end
  end

  def seen(%__MODULE__{mails: mails} = mc, docid) do
    case Map.get(mails, docid) do
      nil -> mc
      %{flags: flags} = headers ->
	case Enum.member?(flags, :seen) do
	  true -> mc
	  false ->
	    MaildirCommander.flag(docid, "+S")
	    headers = %{headers |
			flags: [:seen | Enum.reject(flags, &(&1 == :unread))]}
	    %{mc | mails: %{mails | docid => headers}}
	end
    end
  end	

  @doc """
  getter of a specific mail metadata
  """
  def mail_meta(%__MODULE__{mails: mails}, docid), do: Map.get(mails, docid)

  @doc """
  getter of the html content
  """
  def html_content(%__MODULE__{contents: contents}, docid) do
    case Map.get(contents, docid) do
      nil ->
	case MaildirCommander.full_mail(docid) do
	  {:error, msg} -> raise(msg)
 	  {_, text, html} -> html_mail(text, html)
	end
      content -> content
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

  defp html_mail("", "") do
    ~s"""
    <!DOCTYPE html><html>
    <head><meta charset="utf-8"/></head>
    <body><h1>No text in the mail</h1></body></html>
    """
  end

  defp html_mail(text, "") do
    ~s"""
    <!DOCTYPE html><html>
    <head><meta charset="utf-8"/></head>
    <body><pre>#{text}</pre></body></html>
    """
  end

  defp html_mail(_text, html), do: html

end

