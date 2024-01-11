defmodule Liv.MailClient do
  require Logger
  alias Liv.{Configer, Mailer, AddressVault, DraftServer}
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
  reindex in the background
  """
  def reindex() do
    spawn_link(MaildirCommander, :index, [])
  end

  @doc """
  wake up the mc process. It is an optimization
  """
  def snooze(), do: MaildirCommander.snooze()

  @doc """
  run a query. query can be a query string or a docid integer
  """
  def new_search(query) do
    # we piggy back pop to new mail query
    if String.match?(query, ~r/flag:unread/), do: pop_all()

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
  return the replied mails from an addr
  """
  def dates_from(addr) do
    case MaildirCommander.find(
           "from:#{addr} flag:replied",
           false,
           :":date",
           false,
           true,
           false
         ) do
      {:error, msg} ->
        raise(msg)

      {:ok, tree, mails} ->
        tree
        |> MCTree.root_list()
        |> Enum.map(fn docid -> mails |> Map.fetch!(docid) |> Map.fetch!(:date) end)
    end
  end

  @doc """
  close a message by setting docid to 0 and mark the old message seen
  """
  def close(nil), do: nil
  def close(%__MODULE__{docid: 0} = mc), do: mc

  def close(%__MODULE__{mails: mails, docid: docid} = mc) do
    case Map.get(mails, docid) do
      nil ->
        %{mc | docid: 0}

      %{flags: flags} ->
        case Enum.member?(flags, :seen) do
          true ->
            %{mc | docid: 0}

          false ->
            case MaildirCommander.flag(docid, "+S") do
              {:ok, m} ->
                # broadcast the event
                PubSub.local_broadcast_from(
                  Liv.PubSub,
                  self(),
                  "messages",
                  {:seen_message, docid, m}
                )

                %{mc | mails: %{mails | docid => m}, docid: 0}

              {:error, msg} ->
                Logger.warning("docid: #{docid} #{msg}")
                reindex()
                %{mc | docid: 0}
            end
        end
    end
  end

  @doc """
  open a message. if the mc is nil, make a minimum mc first.
  then stream the content of the mail
  """
  def open(nil, docid) do
    case MaildirCommander.view(docid) do
      {:error, msg} ->
        Logger.warning("docid: #{docid} not found: #{msg}")
        reindex()
        nil

      {:ok, %{path: path} = meta} ->
        Logger.debug("streaming #{path}")

        case MaildirCommander.stream_mail(path) do
          {:error, reason} ->
            Logger.warning("docid: #{docid} path: #{path} not found: #{reason}")
            reindex()
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

  def open(mc, docid) do
    %__MODULE__{mails: mails} = mc = close(mc)

    case Map.get(mails, docid) do
      nil ->
        mc

      %{path: path} ->
        Logger.debug("streaming #{path}")

        case MaildirCommander.stream_mail(path) do
          {:error, reason} ->
            Logger.warning("docid: #{docid} path: #{path} not found: #{reason}")
            reindex()
            %{mc | docid: docid, ref: nil}

          {:ok, ref} ->
            %{mc | docid: docid, ref: ref}
        end
    end
  end

  @doc """
  getter of a specific mail metadata
  """
  def mail_meta(nil, _docid), do: nil
  def mail_meta(%__MODULE__{mails: mails}, docid), do: Map.get(mails, docid)

  @doc """
  getter of the ref in string format
  """
  def ref_string(%__MODULE__{ref: ref}), do: ref |> :erlang.ref_to_list() |> to_string()

  @doc """
  setter of a specific mail metadata. nil is delete
  """
  def set_meta(nil, _docid, _meta), do: nil

  def set_meta(%__MODULE__{mails: mails} = mc, docid, nil) do
    %{mc | mails: Map.delete(mails, docid)}
  end

  def set_meta(%__MODULE__{mails: mails} = mc, docid, meta) do
    %{mc | mails: Map.replace(mails, docid, meta)}
  end

  @doc """
  the query that get one mail
  """
  def solo_query(%__MODULE__{mails: mails, docid: docid}), do: "msgid:#{mails[docid].msgid}"

  @doc """
  the query that get all mails from sender
  """
  def from_query(%__MODULE__{mails: mails, docid: docid}), do: "from:#{tl(mails[docid].from)}"

  @doc """
  getter of the text content in quote
  """
  def quoted_text(_, nil), do: nil
  def quoted_text(_, ""), do: ""
  def quoted_text(nil, text), do: "> #{text}\n"

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
    case URI.parse(mailto) do
      %URI{scheme: "mailto", path: tos, query: nil} ->
        {get_recipients(tos), nil, nil}

      %URI{scheme: "mailto", path: tos, query: query} ->
        query = query |> URI.query_decoder() |> Enum.to_list()

        {get_recipients(tos), :proplists.get_value("subject", query, nil),
         :proplists.get_value("body", query, nil)}

      %URI{path: nil} ->
        {[], nil, nil}

      %URI{path: to_addr} ->
        {get_recipients([to_addr]), nil, nil}
    end
  end

  defp get_recipients(nil), do: []
  defp get_recipients([]), do: []

  defp get_recipients(str) when is_binary(str) do
    str |> String.split(~r/\s*,\s*/) |> get_recipients()
  end

  defp get_recipients(tos) do
    [name | addr] = Configer.default(:my_address)

    bccs =
      case Enum.member?(tos, addr) do
        true -> []
        false -> [{:bcc, [name | addr]}]
      end

    tos = Enum.map(tos, fn addr -> {:to, [nil | addr]} end)

    tos ++ bccs
  end

  @doc """
  default recipients
  """
  def default_recipients(), do: [{:to, [nil | ""]}, {:bcc, Configer.default(:my_address)}]

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
      )
    ])
  end

  @doc """
  normalize recipients, in the orfer of to, cc, bcc
  """
  def normalize_recipients(recipients) do
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
  def parse_recipient("", _), do: {nil, [nil | ""]}

  @doc """
  send a mail
  """
  def send_mail(subject, recipients, text, msgid \\ nil, references \\ [], atts \\ [])

  def send_mail("", _, _, _, _, _), do: {:error, "no subject"}
  def send_mail(_, _, "", _, _, _), do: {:error, "no text"}

  def send_mail(subject, [{:to, _} | _] = recipients, text, msgid, references, atts) do
    import Swoosh.Email

    case DraftServer.html(text) do
      {:ok, html} ->
        try do
          new()
          |> from(addr_to_swoosh(Configer.default(:my_address)))
          |> subject(subject)
          |> add_recipients(recipients)
          |> add_references(msgid, references)
          |> header("X-Mailer", "LivMail 0.1.0")
          |> text_body(DraftServer.text(text))
          |> html_body(html)
          |> add_attachments(atts)
          |> Mailer.deliver()

          DraftServer.clear_draft()
        rescue
          _e -> {:error, "deliver failed"}
        end

      {:error, e} ->
        {:error, e}
    end
  end

  def send_mail(_, _, _, _, _, _), do: {:error, "no To: recipient"}

  @doc """
  Send the html draft from draft server, draft is kept for future usage
  """
  def send_draft(name, addr) do
    import Swoosh.Email

    case DraftServer.get_draft() do
      {nil, _, _, _, _} ->
        {:error, "no subject"}

      {_, _, nil, _, _} ->
        {:error, "no draft"}

      {subject, _recipients, draft, msgid, references} ->
        case DraftServer.html(draft, %{name: name, addr: addr}) do
          {:ok, html} ->
            try do
              new()
              |> from(addr_to_swoosh(Configer.default(:my_address)))
              |> subject(subject)
              |> to({name, addr})
              |> add_references(msgid, references)
              |> header("X-Mailer", "LivMail 0.1.0")
              |> text_body(DraftServer.text(draft))
              |> html_body(html)
              |> Mailer.deliver()

              DraftServer.put_draft(subject, [to: [name | addr]], draft, msgid, references)
            rescue
              _e -> {:error, "deliver failed"}
            end

          {:error, e} ->
            {:error, e}
        end
    end
  end

  @doc """
  getter of the default reply subject
  """
  def reply_subject(%__MODULE__{docid: docid, mails: mails}) when docid > 0 do
    case mails[docid].subject do
      "" ->
        ""

      sub ->
        case Regex.run(~r/^re:\s*(.*)/i, sub) do
          nil -> "Re: " <> sub
          [_, ""] -> ""
          [_, str] -> "Re: " <> str
        end
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
  def receive_part(%__MODULE__{ref: ref}, ref, :eof), do: :eof

  def receive_part(%__MODULE__{ref: ref}, ref, %{content_type: "text/plain", body: body}) do
    {"", "text/plain", body}
  end

  def receive_part(%__MODULE__{ref: ref}, ref, %{content_type: "text/html", body: body}) do
    {"", "text/html", body}
  end

  def receive_part(%__MODULE__{ref: ref}, ref, %{
        content_type: type,
        disposition_params: %{"filename" => filename},
        body: body
      })
      when filename != "" do
    {filename, type, body}
  end

  def receive_part(%__MODULE__{ref: ref}, ref, %{
        content_type: type,
        content_type_params: %{"name" => filename},
        disposition: "attachment",
        body: body
      })
      when filename != "" do
    {filename, type, body}
  end

  def receive_part(_, _, _), do: nil

  @doc """
  archiving job. Always return :ok. will log and do side effects
  """
  def archive_job() do
    case MaildirCommander.find_all("maildir:/", true, :":date", false, false, false) do
      {:error, reason} ->
        Logger.warning("query error: #{reason}")

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

  @doc """
  broadcast new mail arrival
  """
  def notify_new_mail(), do: PubSub.local_broadcast(Liv.PubSub, "world", :new_mail)

  defp pop_all() do
    :remote_mail_boxes
    |> Configer.default()
    |> Enum.each(fn %{method: "pop3", username: user, password: pass, hostname: host} ->
      MaildirCommander.pop_all(user, pass, host)
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

  defp add_attachments(email, atts) do
    import Swoosh.Email

    atts
    |> Enum.reverse()
    |> Enum.reduce(email, fn {name, _size, data}, mail ->
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
  end

  defp add_references(email, nil, _), do: email

  defp add_references(email, msgid, references) do
    import Swoosh.Email
    # prevent very long reference chain
    references =
      references
      |> Enum.take(9)
      |> Kernel.++([msgid])
      |> Enum.map(fn str -> "<#{str}>" end)
      |> Enum.join(" ")

    email
    |> header("In-Reply-To", "<#{msgid}>")
    |> header("References", references)
  end

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
        # broadcast the event
        PubSub.local_broadcast(Liv.PubSub, "messages", {:delete_message, docid})
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
        {:ok, mail} = MaildirCommander.move(docid, archive)
        # broadcast the event
        PubSub.local_broadcast(Liv.PubSub, "messages", {:archive_message, docid, mail})
      end,
      list,
      tree
    )
  end

  # the flag replied is used to mark messages for archiving
  defp mark_conversations(list, tree, messages) do
    MCTree.traverse(
      fn docid ->
        %{flags: flags} = Map.get(messages, docid)

        unless Enum.member?(flags, :replied) do
          Logger.notice("marking mail (#{docid})")
          {:ok, mail} = MaildirCommander.flag(docid, "+R")
          # broadcast the event
          PubSub.local_broadcast(Liv.PubSub, "messages", {:mark_message, docid, mail})
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
          {:ok, mail} = MaildirCommander.flag(docid, "-R")
          # broadcast the event
          PubSub.local_broadcast(Liv.PubSub, "messages", {:unmark_message, docid, mail})
        end
      end,
      list,
      tree
    )
  end
end
