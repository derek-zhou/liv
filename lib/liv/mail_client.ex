defmodule Liv.MailClient do
  require Logger
  alias Liv.Configer
  alias Liv.Mailer
  alias Liv.AddressVault
  alias Phoenix.PubSub

  @moduledoc """
  The core MailClient state mamangment abstracted from the UI. 
  """

  alias :maildir_commander, as: MaildirCommander
  alias :mc_tree, as: MCTree

  defstruct [
    :tree,
    mails: %{},
    docid: 0,
    ref: nil
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
           false,
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
    case MaildirCommander.view(docid) do
      {:error, msg} ->
        Logger.warn("docid: #{docid} not found: #{msg}")
        nil

      {:ok, meta} ->
        %{path: path} =
          meta =
          case Enum.member?(meta.flags, :seen) do
            true ->
              meta

            false ->
              {:ok, m} = MaildirCommander.flag(docid, "+S")
              m
          end

        Logger.debug("streaming #{path}")

        case MaildirCommander.stream_mail(path) do
          {:error, reason} ->
            Logger.warn("docid: #{docid} path: #{path} not found: #{reason}")
            nil

          {:ok, ref} ->
            %__MODULE__{
              tree: MCTree.single(docid),
              mails: %{docid => meta},
              docid: docid,
              ref: ref
            }
        end
    end
  end

  def seen(%__MODULE__{docid: docid} = mc, docid), do: mc

  def seen(%__MODULE__{mails: mails} = mc, docid) do
    case Map.get(mails, docid) do
      nil ->
        mc

      %{flags: flags} ->
        mc =
          case Enum.member?(flags, :seen) do
            true ->
              %{mc | docid: docid}

            false ->
              {:ok, m} = MaildirCommander.flag(docid, "+S")
              %{mc | docid: docid, mails: %{mails | docid => m}}
          end

        %{path: path} = mc.mails[docid]
        Logger.debug("streaming #{path}")

        case MaildirCommander.stream_mail(path) do
          {:error, reason} ->
            Logger.warn("docid: #{docid} path: #{path} not found: #{reason}")
            %{mc | ref: nil}

          {:ok, ref} ->
            %{mc | ref: ref}
        end
    end
  end

  @doc """
  getter of a specific mail metadata
  """
  def mail_meta(nil, _docid), do: nil
  def mail_meta(%__MODULE__{mails: mails}, docid), do: Map.get(mails, docid)

  @doc """
  getter of the text content in quote
  """
  def quoted_text(_, ""), do: ""
  def quoted_text(nil, _), do: ""

  def quoted_text(%__MODULE__{mails: mails, docid: docid}, text) do
    case Map.get(mails, docid) do
      nil ->
        ""

      meta ->
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
  getter of default to and subject from mailto: link. everything else are ignored for now
  """
  def parse_mailto(mailto) do
    [name | addr] = Configer.default(:my_address)

    case URI.parse(mailto) do
      %URI{scheme: "mailto", path: tos, query: query} ->
        tos =
          tos
          |> String.split(~r/\s*,\s*/)
          |> Enum.map(fn addr -> {:to, [nil | addr]} end)

        bccs =
          case List.keymember?(tos, [nil | addr], 1) do
            true -> []
            false -> [{:bcc, [name | addr]}]
          end

        sub =
          case query do
            nil ->
              ""

            _ ->
              query
              |> URI.query_decoder()
              |> Enum.reduce("", fn
                {"subject", v}, _ -> v
                {_, _}, sub -> sub
              end)
          end

        {tos ++ bccs, sub}

      %URI{path: ^addr} ->
        {[{:to, [name | addr]}], ""}

      %URI{path: to_addr} ->
        {[{:to, [nil | to_addr]}, {:bcc, [name | addr]}], ""}
    end
  end

  @doc """
  getter of default to, cc and bcc for this email
  """
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
  receive parts into data structure.
  """
  def receive_part(%__MODULE__{ref: ref}, ref, %{content_type: "text/plain", body: body}) do
    {:text, body}
  end

  def receive_part(%__MODULE__{ref: ref}, ref, %{content_type: "text/html", body: body}) do
    {:html, body}
  end

  def receive_part(%__MODULE__{ref: ref}, ref, %{
        content_type: type,
        disposition_params: %{"filename" => filename},
        body: body
      }) do
    {:attachment, filename, type, body}
  end

  def receive_part(_, _, _), do: nil

  @doc """
  archiving job. Always return :ok. will log and do side effects
  """
  def archive_job() do
    case MaildirCommander.find("maildir:/", true, :":date", false, false, false) do
      {:error, reason} ->
        Logger.warn("query error: #{reason}")

      {:ok, tree, messages} ->
        horizon = System.system_time(:second) - Configer.default(:archive_days) * 86400
        archive = String.to_charlist(Configer.default(:archive_maildir))
        my_addresses = MapSet.new(Configer.default(:my_addresses))
        is_recent = &is_recent(Map.get(messages, &1), horizon)
        is_important = &is_important(Map.get(messages, &1), my_addresses)

        {mark_list, unmark_list} =
          tree
          |> MCTree.root_list()
          |> Enum.split_with(&MCTree.any(is_important, &1, tree))

        marked = mark_conversations(mark_list, tree, messages)
        unmarked = unmark_conversations(unmark_list, tree, messages)
        Logger.notice("#{marked} mails marked, #{unmarked} mails unmarked")
        archive_list = Enum.reject(mark_list, &MCTree.any(is_recent, &1, tree))
        junk_list = Enum.reject(unmark_list, &MCTree.any(is_recent, &1, tree))

        Logger.notice(
          "#{length(archive_list)} conversations to be archived, #{length(junk_list)} conversation to be deleted"
        )

        case archive do
          "" ->
            Logger.notice("Archiving disabled")

          _ ->
            deleted = delete_conversations(junk_list, tree, messages)
            archived = archive_conversations(archive_list, archive, tree, messages)
            Logger.notice("Done, #{archived} mails archived, #{deleted} mails deleted")
        end
    end

    :ok
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

  defp is_recent(%{date: date}, horizon) when date > horizon, do: true
  defp is_recent(%{flags: flags}, _horizon), do: Enum.member?(flags, :unread)

  defp is_important(%{from: [_name | addr]}, my_addresses) do
    MapSet.member?(my_addresses, addr)
  end

  defp delete_conversations(list, tree, messages) do
    MCTree.traverse(
      fn docid ->
        %{path: path} = Map.get(messages, docid)
        Logger.notice("deleting mail (#{docid}) #{path}")
        MaildirCommander.delete(docid)
      end,
      list,
      tree
    )
  end

  defp archive_conversations(list, archive, tree, messages) do
    MCTree.traverse(
      fn docid ->
        %{path: path} = Map.get(messages, docid)
        Logger.notice("archiving mail (#{docid}) #{path}")
        MaildirCommander.scrub(path)
        {:ok, _} = MaildirCommander.move(docid, archive)
      end,
      list,
      tree
    )
  end

  # the flag replied is used to mark messages for archiving
  defp mark_conversations(list, tree, messages) do
    MCTree.traverse(
      fn docid ->
        mail = %{flags: flags} = Map.get(messages, docid)

        unless Enum.member?(flags, :replied) do
          Logger.notice("marking mail (#{docid})")
          # broadcast the event
          PubSub.local_broadcast(Liv.PubSub, "mark_message", {:mark_message, docid, mail})
          {:ok, _} = MaildirCommander.flag(docid, "+R")
        end
      end,
      list,
      tree
    )
  end

  defp unmark_conversations(list, tree, messages) do
    MCTree.traverse(
      fn docid ->
        %{flags: flags} = Map.get(messages, docid)

        if Enum.member?(flags, :replied) do
          Logger.notice("unmarking mail (#{docid})")
          # broadcast the event
          PubSub.local_broadcast(Liv.PubSub, "unmark_message", {:unmark_message, docid})
          {:ok, _} = MaildirCommander.flag(docid, "-R")
        end
      end,
      list,
      tree
    )
  end
end
