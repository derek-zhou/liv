defmodule Liv.MailClient do
  require Logger
  alias Liv.Configer
  alias Liv.Mailer
  alias Liv.AddressVault

  @moduledoc """
  The core MailClient state mamangment abstracted from the UI. 
  """

  alias :maildir_commander, as: MaildirCommander
  alias :mc_tree, as: MCTree

  defstruct [
    :tree,
    mails: %{},
    docid: 0,
    parts: [],
    contents: {}
  ]

  @doc """
  run a query. query can be a query string or a docid integer
  """
  def new_search(query) do
    case MaildirCommander.find(
           query,
           true,
           :":date",
           true,
           true,
           String.match?(query, ~r/^msgid:/)
         ) do
      {:error, msg} ->
        raise(msg)

      {:ok, tree, mails} ->
        %__MODULE__{tree: MCTree.collapse(tree), mails: mails}
    end
  end

  @doc """
  mark a message seen. if the mc is nil, make a minimum mc first
  """
  def seen(nil, docid) do
    case MaildirCommander.full_mail(docid) do
      {:error, msg} ->
        raise(msg)

      {meta, text, html, parts} ->
        meta =
          case Enum.member?(meta.flags, :seen) do
            true ->
              meta

            false ->
              MaildirCommander.flag(docid, "+S")
              %{meta | flags: [:seen | Enum.reject(meta.flags, &(&1 == :unread))]}
          end

        %__MODULE__{
          tree: MCTree.single(docid),
          mails: %{docid => meta},
          docid: docid,
          parts: parts,
          contents: {text, html}
        }
    end
  end

  def seen(%__MODULE__{docid: docid} = mc, docid), do: mc

  def seen(%__MODULE__{mails: mails} = mc, docid) do
    case Map.get(mails, docid) do
      nil ->
        mc

      %{flags: flags} = headers ->
        {_, text, html, parts} = MaildirCommander.full_mail(docid)
        mc = %{mc | docid: docid, parts: parts, contents: {text, html}}

        case Enum.member?(flags, :seen) do
          true ->
            mc

          false ->
            MaildirCommander.flag(docid, "+S")
            headers = %{headers | flags: [:seen | Enum.reject(flags, &(&1 == :unread))]}
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
  def html_content(%__MODULE__{contents: {text, html}}), do: html_mail(text, html)
  def html_content(_), do: html_mail("", "")

  @doc """
  getter of the text content
  """
  def text_content(%__MODULE__{contents: {text, _}}), do: text
  def text_content(_), do: ""

  @doc """
  getter of the text content in quote
  """
  def quoted_text(mc) do
    case text_content(mc) do
      "" ->
        ""

      text ->
        meta = mc.mails[mc.docid]
        {:ok, date} = DateTime.from_unix(meta.date)

        IO.chardata_to_string([
          "On #{date}, #{hd(meta.from)} wrote:\n",
          text
          |> String.split(~r/\n/)
          |> Enum.map(fn str -> "> #{str}\n" end)
        ])
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
    MCTree.traverse(
      fn docid ->
        case Map.get(mails, docid) do
          %{flags: flags} ->
            case Enum.member?(flags, :seen) do
              true -> nil
              false -> :ok
            end

          _ ->
            nil
        end
      end,
      tree
    )
  end

  @doc """
  test if a docid is in the client
  """
  def contains?(%__MODULE__{mails: mails}, docid) do
    Map.has_key?(mails, docid)
  end

  @doc """
  predicate of first
  """
  def is_first(%__MODULE__{tree: tree}, docid), do: docid == MCTree.first(tree)

  @doc """
  predicate of last
  """
  def is_last(%__MODULE__{tree: tree}, docid), do: docid == MCTree.last(tree)

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
  def children_of(nil, _), do: []
  def children_of(tree, docid), do: MCTree.children(docid || :undefined, tree)

  @doc """
  getter of the tree
  """
  def tree_of(nil), do: nil
  def tree_of(%__MODULE__{tree: tree}), do: tree

  @doc """
  getter of mails
  """
  def mails_of(nil), do: %{}
  def mails_of(%__MODULE__{mails: mails}), do: mails

  @doc """
  getter of default to, cc and bcc for this email
  """
  def default_recipients(nil, to_addr) do
    List.flatten([
      {:to, default_to(%{}, to_addr)},
      Enum.map(
        default_bcc(%{}, to_addr, Configer.default(:my_address)),
        &{:bcc, &1}
      ),
      {nil, [nil | ""]}
    ])
  end

  def default_recipients(mc, to_addr) do
    addr_map = addresses_map(mc)

    List.flatten([
      {:to, default_to(addr_map, to_addr)},
      Enum.map(default_cc(addr_map, to_addr), &{:cc, &1}),
      Enum.map(
        default_bcc(addr_map, to_addr, Configer.default(:my_address)),
        &{:bcc, &1}
      ),
      {nil, [nil | ""]}
    ])
  end

  @doc """
  normalize recipients, in the orfer of to, cc, bcc and one blank
  """
  def normalize_recipients(recipients) do
    List.flatten([
      Enum.filter(recipients, fn {type, _} -> type == :to end),
      Enum.filter(recipients, fn {type, _} -> type == :cc end),
      Enum.filter(recipients, fn {type, _} -> type == :bcc end),
      {nil, [nil | ""]}
    ])
  end

  @doc """
  finalize recipients, in the orfer of to, cc, bcc and one blank
  """
  def finalize_recipients(recipients) do
    List.flatten([
      Enum.filter(recipients, fn {type, _} -> type == :to end),
      Enum.filter(recipients, fn {type, _} -> type == :cc end),
      Enum.filter(recipients, fn {type, _} -> type == :bcc end)
    ])
  end

  @doc """
  parse an addr to a {type, [name | addr]} tuple
  """
  def parse_recipient("to", addr), do: {:to, parse_addr(addr)}
  def parse_recipient("cc", addr), do: {:cc, parse_addr(addr)}
  def parse_recipient("bcc", addr), do: {:bcc, parse_addr(addr)}
  def parse_recipient("nil", _), do: {nil, [nil | ""]}

  @doc """
  send a mail
  """
  def send_mail(_, "", _, _, _), do: {:error, "no subject"}
  def send_mail(_, _, _, "", _), do: {:error, "no text"}

  def send_mail(mc, subject, [{:to, _} | _] = recipients, text, atts) do
    import Swoosh.Email

    try do
      mail =
        new()
        |> from(addr_to_swoosh(Configer.default(:my_address)))
        |> subject(subject)
        |> add_recipients(recipients)
        |> add_references(mc)
        |> header("X-Mailer", "LivMail 0.1.0")
        |> text_body(text)
        |> html_body(Earmark.as_html!(text))

      mail =
        Enum.reduce(atts, mail, fn {name, _size, data}, mail ->
          attachment(
            mail,
            Swoosh.Attachment.new(
              {:data, IO.iodata_to_binary(data)},
              filename: name,
              content_type: MIME.from_path(name),
              type: :attachment
            )
          )
        end)

      Mailer.deliver(mail)
    rescue
      RuntimeError -> {:error, "deliver failed"}
    end
  end

  def send_mail(_, _, _, _), do: {:error, "no To: recipient"}

  @doc """
  getter of the default reply subject
  """
  def reply_subject(%__MODULE__{docid: docid, mails: mails}) when docid > 0 do
    case mails[docid].subject do
      sub = <<"Re: ", _rest::binary>> -> sub
      sub -> "Re: " <> sub
    end
  end

  def reply_subject(_), do: ""

  @doc """
  getter of to name from relevent addresses
  """
  def find_address(mc, to_addr) do
    [Map.get(addresses_map(mc), to_addr) | to_addr]
  end

  @doc """
  load attchments into a list of {name, type, content} tupple
  """
  def load_attachments(%__MODULE__{docid: docid, parts: parts}) do
    temp = System.tmp_dir!() <> "/liv_temp_mail_" <> System.get_env("USER")

    docid
    |> MaildirCommander.extract(parts, temp)
    |> Enum.filter(fn
      {name, :error, msg} ->
        Logger.warn("mail docid #{docid}, attachment #{name} fail to load: #{msg}")
        false

      _ ->
        true
    end)
  end

  defp addresses_map(%__MODULE__{docid: docid, mails: mails}) when docid > 0 do
    %{from: from, to: to, cc: cc} = Map.fetch!(mails, docid)

    map = %{tl(from) => hd(from)}
    map = Enum.reduce(to, map, fn [n | a], m -> Map.put_new(m, a, n) end)
    map = Enum.reduce(cc, map, fn [n | a], m -> Map.put_new(m, a, n) end)

    map
  end

  defp addresses_map(_), do: %{}

  # to is whatever I can find from the map
  defp default_to(_, "#"), do: [nil | ""]
  defp default_to(addr_map, to_addr), do: [Map.get(addr_map, to_addr) | to_addr]

  # cc is addr_map sans to and sans my addresses
  defp default_cc(addr_map, to_addr) do
    my_addresses = default_set(:my_addresses)

    addr_map
    |> Enum.reject(fn {a, _n} ->
      a == to_addr || MapSet.member?(my_addresses, a)
    end)
    |> Enum.map(fn {a, n} -> [n | a] end)
  end

  # bcc is my address, unless to is one of my addresses, or a list is invloved
  defp default_bcc(_, to_addr, [_ | to_addr]), do: []

  defp default_bcc(addr_map, _, my_address) do
    my_lists = default_set(:my_email_lists)

    if Enum.any?(addr_map, fn {a, _n} ->
         MapSet.member?(my_lists, a)
       end),
       do: [],
       else: [my_address]
  end

  defp default_set(atom) do
    atom
    |> Configer.default()
    |> MapSet.new()
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

  defp html_mail(_, html), do: html

  defp parse_addr(str) do
    case Regex.run(~r/(.*)\s+<(.*)>$/, str) do
      [_, name, addr] -> [String.trim(name, "\"") | addr]
      _ -> [nil | str]
    end
  end

  defp addr_to_swoosh([nil | addr]), do: addr
  defp addr_to_swoosh([name | addr]), do: {name, addr}

  defp add_recipients(email, recipients) do
    import Swoosh.Email

    Enum.reduce(recipients, email, fn {type, recipient}, email ->
      AddressVault.add(hd(recipient), tl(recipient))

      case type do
        :to -> to(email, addr_to_swoosh(recipient))
        :cc -> cc(email, addr_to_swoosh(recipient))
        :bcc -> bcc(email, addr_to_swoosh(recipient))
      end
    end)
  end

  defp add_references(email, %__MODULE__{docid: docid, mails: mails}) when docid > 0 do
    import Swoosh.Email
    %{msgid: msgid, references: references} = Map.fetch!(mails, docid)

    references =
      (references ++ [msgid])
      |> Enum.map(fn str -> "<#{str}>" end)
      |> Enum.join(" ")

    email
    |> header("In-Reply-To", "<#{msgid}>")
    |> header("References", references)
  end

  defp add_references(email, _), do: email
end
