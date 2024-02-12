defmodule LivWeb.MailLive do
  use Surface.LiveView
  require Logger

  @default_query "maildir:/"
  @chunk_size 60_000

  alias Liv.{Configer, MailClient, AddressVault, DraftServer, DelayMarker, Shadow}

  alias LivWeb.{
    Main,
    Find,
    Search,
    ViewHeader,
    View,
    Login,
    Guardian,
    Write,
    Config,
    Draft,
    AddressBook,
    Boomerang
  }

  alias LivWeb.Router.Helpers, as: Routes
  alias LivWeb.Endpoint
  alias :self_configer, as: SelfConfiger
  alias Phoenix.LiveView.Socket
  alias Phoenix.PubSub
  import Bitwise

  # client side state
  # nil, logged_in, logged_out
  data auth, :atom, default: nil
  data token, :any, default: nil
  data tz_offset, :integer, default: 0

  # for login
  data password_hash, :string, default: ""
  data saved_password, :string, default: ""
  data password_prompt, :string, default: "Enter your password: "
  data saved_path, :string, default: "/"

  # for the viewer
  data mail_docid, :integer, default: 0
  data mail_attachments, :list, default: []
  data mail_attachment_offset, :integer, default: 0
  data mail_attachment_metas, :list, default: []
  data mail_chunk_outstanding, :boolean, default: false
  data mail_meta, :any, default: nil
  data mail_text, :string, default: ""

  # the mail client app state
  data mail_client, :map, default: nil

  # for the header
  data info, :string, default: "Loading..."
  data buttons, :list, default: []
  data home_link, :string, default: "#"

  # for finder
  data list_mails, :map, default: %{}
  data list_tree, :tuple, default: nil

  # for search
  data default_query, :string, default: @default_query
  data query_examples, :list, default: []

  # for write
  data recipients, :list, default: []
  data addr_options, :list, default: []
  data subject, :string, default: ""
  data write_text, :string, default: ""
  data replying_msgid, :any, default: nil
  data replying_references, :list, default: []
  data preview_html, :string, default: ""
  data write_attachments, :list, default: []
  data current_Attachment, :tuple, default: nil
  data incoming_attachments, :list, default: []
  data write_chunk_outstanding, :boolean, default: false
  data update_preview, :boolean, default: true

  # for config
  data my_addr, :list, default: [nil | "you@example.com"]
  data my_addrs, :list, default: []
  data my_lists, :list, default: []
  data archive_days, :integer, default: 30
  data archive_maildir, :string, default: ""
  data orbit_api_key, :string, default: ""
  data orbit_workspace, :string, default: ""
  # :local, :remote or :sendgrid
  data sending_method, :atom, default: :local
  data sending_data, :map, default: %{username: "", password: "", hostname: "", api_key: ""}
  data reset_password, :string, default: ""
  data remote_mail_boxes, :list, default: []

  # for address book
  data address_book, :any, default: nil
  # :from, :first, :list, :count
  data sorted_by, :atom, default: :from
  data sorted_desc, :boolean, default: false

  def mount(_params, _session, socket) do
    cond do
      connected?(socket) ->
        MailClient.snooze()
        PubSub.subscribe(Liv.PubSub, "messages")
        PubSub.subscribe(Liv.PubSub, "world")
        values = get_connect_params(socket)

        {
          :ok,
          socket
          |> fetch_token(values)
          |> fetch_tz_offset(values)
          |> fetch_locale(values)
        }

      true ->
        {:ok, socket}
    end
  end

  # this is during the static render. Just do nothing
  def handle_params(_params, _url, %Socket{assigns: %{auth: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_params(_params, _url, %Socket{assigns: %{live_action: :login}} = socket) do
    user = System.get_env("USER")

    {
      :noreply,
      socket
      |> clear_flash()
      |> push_event("set_value", %{key: "token", value: ""})
      |> shadow(
        auth: :logged_out,
        token: nil,
        home_link: "#",
        page_title: "Login as #{user}",
        password_hash: Application.get_env(:liv, :password_hash),
        password_prompt: "Enter your password: ",
        info: "Login as #{user}",
        buttons: []
      )
    }
  end

  def handle_params(_params, url, %Socket{assigns: %{auth: :logged_out}} = socket) do
    uri = URI.parse(url)

    case Application.get_env(:liv, :password_hash) do
      nil ->
        # temporarily log user in to set the password
        {
          :noreply,
          socket
          |> shadow(auth: :logged_in, saved_path: uri.path)
          |> push_patch(to: Routes.mail_path(Endpoint, :set_password))
        }

      hash ->
        {
          :noreply,
          socket
          |> shadow(password_hash: hash, saved_path: uri.path)
          |> push_patch(to: Routes.mail_path(Endpoint, :login))
        }
    end
  end

  def handle_params(_params, _url, %Socket{assigns: %{live_action: :set_password}} = socket) do
    user = System.get_env("USER")

    {
      :noreply,
      socket
      |> clear_flash()
      |> shadow(
        info: "Set password of #{user}",
        home_link: "#",
        page_title: "Set password of #{user}",
        password_hash: nil,
        saved_password: "",
        password_prompt: "Pick a password: ",
        buttons: []
      )
    }
  end

  def handle_params(
        %{"query" => query},
        _url,
        %Socket{
          assigns: %{
            live_action: :find,
            mail_client: mc,
            mail_docid: docid
          }
        } = socket
      ) do
    mc = mc |> MailClient.close(docid) |> MailClient.search(query)

    {
      :noreply,
      socket
      |> shadow(
        mail_docid: 0,
        info: "#{MailClient.unread_count(mc)} unread/#{MailClient.mail_count(mc)}",
        home_link: Routes.mail_path(Endpoint, :find, query),
        page_title: query,
        list_mails: MailClient.mails_of(mc),
        list_tree: MailClient.tree_of(mc),
        mail_client: mc,
        buttons: [
          {:patch, "\u{1F527}", Routes.mail_path(Endpoint, :config), false},
          {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
          {:patch, "\u{1F4DD}", Routes.mail_path(Endpoint, :write, "#"), false},
          {:patch, "\u{1F4D2}", Routes.mail_path(Endpoint, :address_book), false}
        ]
      )
    }
  end

  def handle_params(
        %{"docid" => docid},
        _url,
        %Socket{
          assigns: %{
            live_action: :view,
            mail_client: mc,
            mail_docid: old_docid
          }
        } = socket
      ) do
    case Integer.parse(docid) do
      {0, ""} ->
        {:noreply, mail_not_found(socket, mc)}

      {^old_docid, ""} ->
        {:noreply, mail_unchanged(socket, mc, old_docid)}

      {docid, ""} ->
        case MailClient.open(mc, docid) do
          nil -> {:noreply, mail_not_found(socket, mc)}
          mc -> {:noreply, mail_found(socket, mc, docid)}
        end

      _ ->
        {:noreply, mail_not_found(socket, mc)}
    end
  end

  def handle_params(
        _params,
        _url,
        %Socket{
          assigns: %{
            live_action: :search,
            mail_docid: 0,
            mail_client: mc
          }
        } = socket
      ) do
    examples =
      [
        {"The inbox", "maildir:/"},
        {"Unread mails", "flag:unread"},
        {"Last 7 days", "date:7d..now flag:replied"}
      ]

    query = if mc, do: mc.query, else: elem(hd(examples), 1)
    MailClient.snooze()

    {
      :noreply,
      socket
      |> shadow(
        default_query: query,
        query_examples: examples,
        page_title: "Search",
        info: "Search",
        home_link: "#",
        buttons: [
          {:button, "\u{2716}", "close_dialog", false}
        ]
      )
    }
  end

  def handle_params(
        _params,
        _url,
        %Socket{
          assigns: %{
            live_action: :search,
            mail_docid: docid,
            mail_client: mc
          }
        } = socket
      ) do
    examples =
      [
        {"Same thread", MailClient.solo_query(mc, docid)},
        {"Same sender", MailClient.from_query(mc, docid)},
        {"Last query", mc.query}
      ]

    query = if mc, do: mc.query, else: elem(hd(examples), 1)
    MailClient.snooze()

    {
      :noreply,
      socket
      |> shadow(
        default_query: query,
        query_examples: examples,
        page_title: "Search",
        info: "Search",
        home_link: "#",
        buttons: [
          {:button, "\u{2716}", "close_dialog", false}
        ]
      )
    }
  end

  def handle_params(
        _params,
        _url,
        %Socket{assigns: %{live_action: :config}} = socket
      ) do
    {sending_method, sending_data} = Configer.default(:sending_method)

    {
      :noreply,
      socket
      |> shadow(
        page_title: "Config",
        info: "Config",
        my_addr: Configer.default(:my_address),
        my_addrs: Configer.default(:my_addresses),
        my_lists: Configer.default(:my_email_lists),
        archive_days: Configer.default(:archive_days),
        archive_maildir: Configer.default(:archive_maildir),
        orbit_api_key: Configer.default(:orbit_api_key),
        orbit_workspace: Configer.default(:orbit_workspace),
        remote_mail_boxes: Configer.default(:remote_mail_boxes),
        sending_method: sending_method,
        sending_data: sending_data,
        reset_password: "",
        buttons: [
          {:button, "\u{2716}", "close_dialog", false}
        ]
      )
    }
  end

  def handle_params(_params, _url, %Socket{assigns: %{live_action: :draft}} = socket) do
    {subject, recipients, text, msgid, refs} = DraftServer.get_draft()

    {
      :noreply,
      socket
      |> shadow(
        page_title: "Draft",
        info: subject || "",
        home_link: "#",
        recipients: recipients,
        subject: subject || "",
        write_text: text || "",
        replying_msgid: msgid,
        replying_references: refs,
        write_attachments: [],
        buttons: [
          {:patch, "\u{1F4DD}", Routes.mail_path(Endpoint, :write, "#draft"), false},
          {:button, "\u{2716}", "close_write", false}
        ]
      )
    }
  end

  def handle_params(
        %{"to" => "#draft"},
        _url,
        %Socket{assigns: %{live_action: :write}} = socket
      ) do
    {subject, recipients, text, msgid, refs} = DraftServer.get_draft()

    {
      :noreply,
      socket
      |> shadow(
        page_title: "Write",
        info: "",
        home_link: "#",
        incoming_attachments: [],
        current_attachment: nil,
        write_chunk_outstanding: false,
        recipients: recipients,
        subject: subject || "",
        write_text: text || "",
        replying_msgid: msgid,
        replying_references: refs,
        write_attachments: [],
        buttons: [
          {:attach, "\u{1F4CE}", "write_attach", false},
          {:button, "\u{1F5D1}", "drop_attachments", false},
          {:patch, "\u{1F4C3}", Routes.mail_path(Endpoint, :draft), false},
          {:button, "\u{2716}", "close_write", false}
        ]
      )
    }
  end

  def handle_params(
        %{"to" => to},
        _url,
        %Socket{assigns: %{live_action: :write, mail_docid: 0}} = socket
      ) do
    {recipients, subject, text} = MailClient.parse_mailto(to)
    {d_subject, d_recipients, d_text, msgid, refs} = DraftServer.get_draft()

    recipients =
      case {recipients, d_recipients} do
        {[], []} -> MailClient.default_recipients()
        {[], _} -> d_recipients
        _ -> recipients
      end

    {
      :noreply,
      socket
      |> shadow(
        page_title: "Write",
        info: "",
        home_link: "#",
        recipients: recipients,
        subject: subject || d_subject || "",
        write_text: MailClient.quoted_text(nil, 0, text) || d_text || "",
        write_attachments: [],
        replying_msgid: msgid,
        replying_references: refs,
        incoming_attachments: [],
        current_attachment: nil,
        write_chunk_outstanding: false,
        buttons: [
          {:attach, "\u{1F4CE}", "write_attach", false},
          {:button, "\u{1F5D1}", "drop_attachments", false},
          {:patch, "\u{1F4C3}", Routes.mail_path(Endpoint, :draft), false},
          {:button, "\u{2716}", "close_write", false}
        ]
      )
    }
  end

  def handle_params(
        %{"to" => to},
        _url,
        %Socket{
          assigns: %{live_action: :write, mail_client: mc, mail_docid: docid, mail_text: text}
        } = socket
      ) do
    {msgid, refs} =
      case MailClient.mail_meta(mc, docid) do
        %{msgid: msgid, references: refs} -> {msgid, refs}
        _ -> {nil, []}
      end

    {
      :noreply,
      socket
      |> shadow(
        page_title: "Write",
        info: "",
        home_link: "#",
        recipients: MailClient.default_recipients(mc, docid, to),
        subject: MailClient.reply_subject(mc, docid),
        write_text: MailClient.quoted_text(mc, docid, text),
        write_attachments: [],
        replying_msgid: msgid,
        replying_references: refs,
        incoming_attachments: [],
        current_attachment: nil,
        write_chunk_outstanding: false,
        buttons: [
          {:attach, "\u{1F4CE}", "write_attach", false},
          {:button, "\u{1F5D1}", "drop_attachments", false},
          {:patch, "\u{1F4C3}", Routes.mail_path(Endpoint, :draft), false},
          {:button, "\u{2716}", "close_write", false}
        ]
      )
    }
  end

  def handle_params(
        %{
          "sorted_by" => sorted_by,
          "desc" => desc
        },
        _url,
        %Socket{
          assigns: %{
            live_action: :address_book,
            address_book: book
          }
        } = socket
      ) do
    sorted_by =
      case sorted_by do
        "first" -> :first
        "last" -> :last
        "count" -> :count
        _ -> :from
      end

    desc =
      case desc do
        "1" -> true
        "t" -> true
        "true" -> true
        _ -> false
      end

    book = sort_address_book(book || Liv.AddressVault.all_entries(), sorted_by, desc)

    {
      :noreply,
      socket
      |> shadow(
        page_title: "My address book",
        info: "#{Enum.count(book)} correspondents",
        home_link: "#",
        address_book: book,
        sorted_by: sorted_by,
        sorted_desc: desc,
        buttons: [
          {:button, "\u{2716}", "close_dialog", false}
        ]
      )
    }
  end

  def handle_params(
        _params,
        _url,
        %Socket{
          assigns: %{
            live_action: :address_book,
            sorted_by: sorted_by,
            sorted_desc: desc
          }
        } = socket
      ) do
    book = sort_address_book(Liv.AddressVault.all_entries(), sorted_by, desc)

    {
      :noreply,
      socket
      |> shadow(
        page_title: "My address book",
        info: "#{Enum.count(book)} correspondents",
        home_link: "#",
        address_book: book,
        sorted_by: sorted_by,
        sorted_desc: desc,
        buttons: [
          {:button, "\u{2716}", "close_dialog", false}
        ]
      )
    }
  end

  def handle_params(
        _params,
        _url,
        %Socket{assigns: %{live_action: :boomerang}} = socket
      ) do
    {
      :noreply,
      shadow(socket,
        info: "Boomerang a Mail",
        home_link: "#",
        page_title: "Boomerang a Mail",
        buttons: [
          {:button, "\u{2716}", "close_dialog", false}
        ]
      )
    }
  end

  def handle_params(_params, _url, %Socket{assigns: %{mail_client: mc}} = socket) do
    if mc && mc.query do
      {:noreply, push_patch(socket, to: Routes.mail_path(Endpoint, :find, mc.query))}
    else
      {:noreply, push_patch(socket, to: Routes.mail_path(Endpoint, :find, @default_query))}
    end
  end

  def handle_event(
        "boomerang_submit",
        %{"hours" => hours},
        %Socket{assigns: %{mail_docid: docid}} = socket
      ) do
    DelayMarker.flag(docid, String.to_integer(hours) * 3600)
    {:noreply, push_patch(socket, to: close_action(socket))}
  end

  def handle_event(
        "pw_submit",
        %{"password" => ""},
        %Socket{assigns: %{password_hash: nil, saved_password: ""}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event(
        "pw_submit",
        %{"password" => password},
        %Socket{assigns: %{password_hash: nil, saved_password: ""}} = socket
      ) do
    {
      :noreply,
      socket
      |> clear_flash()
      |> shadow(
        saved_password: password,
        password_prompt: "Re-enter the password: "
      )
    }
  end

  def handle_event(
        "pw_submit",
        %{"password" => password},
        %Socket{assigns: %{saved_path: path, password_hash: nil, saved_password: password}} =
          socket
      ) do
    hash = Argon2.hash_pwd_salt(password)
    SelfConfiger.set_env(Configer, :password_hash, hash)

    {
      :noreply,
      socket
      |> clear_flash()
      |> shadow(password_hash: hash)
      |> push_patch(to: path)
    }
  end

  def handle_event("pw_submit", _, %Socket{assigns: %{password_hash: nil}} = socket) do
    {
      :noreply,
      socket
      |> put_flash(:error, "Passwords do not match")
      |> shadow(
        saved_password: "",
        password_prompt: "Enter your password: "
      )
    }
  end

  def handle_event(
        "pw_submit",
        %{"password" => password},
        %Socket{assigns: %{saved_path: path, password_hash: hash}} = socket
      ) do
    case Argon2.verify_pass(password, hash) do
      true ->
        token = Guardian.build_token()
        Shadow.start(token)

        {
          :noreply,
          socket
          |> clear_flash()
          |> push_event("set_value", %{key: "token", value: Base.url_encode64(token)})
          |> shadow(auth: :logged_in, token: token)
          |> push_patch(to: path)
        }

      false ->
        {:noreply, put_flash(socket, :error, "Login failed")}
    end
  end

  def handle_event("search", %{"query" => ""}, socket) do
    {:noreply, put_flash(socket, :error, "Query cannot be empty")}
  end

  def handle_event("search", %{"query" => query}, socket) do
    {
      :noreply,
      socket
      |> shadow(mail_client: nil)
      |> push_patch(to: Routes.mail_path(Endpoint, :find, query))
    }
  end

  def handle_event("pick_search_example", %{"query" => query}, socket) do
    {:noreply, shadow(socket, default_query: query)}
  end

  def handle_event(
        "delete_address",
        %{"address" => addr},
        %Socket{assigns: %{address_book: book}} = socket
      ) do
    AddressVault.remove(addr)
    book = Enum.reject(book, fn entry -> entry.addr == addr end)

    {:noreply,
     shadow(socket,
       info: "#{Enum.count(book)} correspondents",
       address_book: book
     )}
  end

  def handle_event(
        "write_change",
        %{
          "_target" => [target | _],
          "subject" => subject,
          "text" => text,
          "update_preview" => update
        } = mail,
        %Socket{
          assigns: %{
            recipients: recipients,
            replying_msgid: msgid,
            replying_references: refs
          }
        } = socket
      ) do
    completion_list =
      cond do
        !String.starts_with?(target, "addr_") -> []
        String.length(mail[target]) < 2 -> []
        true -> AddressVault.start_with(mail[target])
      end

    recipients =
      0..length(recipients)
      |> Enum.map(fn i ->
        MailClient.parse_recipient(mail["type_#{i}"], mail["addr_#{i}"])
      end)
      |> MailClient.normalize_recipients()

    DraftServer.put_draft(subject, recipients, text, msgid, refs)

    {
      :noreply,
      shadow(socket,
        recipients: recipients,
        subject: subject,
        addr_options: completion_list,
        write_text: text,
        update_preview: update == "true"
      )
    }
  end

  def handle_event(
        "write_recover",
        %{"subject" => subject, "text" => text, "update_preview" => update} = mail,
        socket
      ) do
    count =
      Enum.count(mail, fn {k, _} ->
        String.starts_with?(k, "addr_")
      end)

    recipients =
      0..(count - 1)
      |> Enum.map(fn i ->
        MailClient.parse_recipient(mail["type_#{i}"], mail["addr_#{i}"])
      end)
      |> Enum.flat_map(fn
        %{method: ""} -> []
        box -> box
      end)

    {_, _, _, msgid, refs} = DraftServer.get_draft()
    DraftServer.put_draft(subject, recipients, text, msgid, refs)

    {
      :noreply,
      shadow(socket,
        recipients: recipients,
        subject: subject,
        write_text: text,
        update_preview: update == "true",
        replying_msgid: msgid,
        replying_references: refs
      )
    }
  end

  def handle_event(
        "send",
        _params,
        %Socket{
          assigns: %{
            auth: :logged_in,
            replying_msgid: msgid,
            replying_references: refs,
            write_attachments: atts,
            current_attachment: nil,
            incoming_attachments: [],
            subject: subject,
            recipients: recipients,
            write_text: text
          }
        } = socket
      ) do
    case MailClient.send_mail(subject, recipients, text, msgid, refs, atts) do
      {:error, msg} ->
        {:noreply, put_flash(socket, :error, "Mail not sent: #{inspect(msg)}")}

      :ok ->
        {
          :noreply,
          socket
          |> put_flash(:info, "Mail sent.")
          |> shadow(
            recipients: [],
            write_text: "",
            subject: "",
            replying_msgid: nil,
            replying_references: [],
            write_attachments: [],
            incoming_attachments: []
          )
          |> push_patch(to: close_action(socket))
        }
    end
  end

  def handle_event("send", _param, socket) do
    {:noreply, put_flash(socket, :warning, "Action temporarily not allowed")}
  end

  def handle_event(
        "close_write",
        _params,
        %Socket{assigns: %{auth: :logged_in, incoming_attachments: [], current_attachment: nil}} =
          socket
      ) do
    DraftServer.clear_draft()

    {
      :noreply,
      socket
      |> shadow(
        recipients: [],
        write_text: "",
        subject: "",
        replying_msgid: nil,
        replying_references: [],
        write_attachments: [],
        incoming_attachments: []
      )
      |> push_patch(to: close_action(socket))
    }
  end

  def handle_event("close_write", _param, socket) do
    {:noreply, put_flash(socket, :warning, "Action temporarily not allowed")}
  end

  def handle_event(
        "config_change",
        %{
          "my_name" => name,
          "my_addr" => addr,
          "my_addrs" => addrs,
          "my_lists" => lists,
          "archive_days" => days,
          "archive_maildir" => maildir,
          "orbit_api_key" => orbit_api_key,
          "orbit_workspace" => workspace,
          "sending_method" => sending_method,
          "username" => username,
          "password" => password,
          "hostname" => hostname,
          "api_key" => api_key,
          "reset_password" => reset_password
        } = config,
        %Socket{
          assigns: %{sending_data: sending_data, remote_mail_boxes: boxes}
        } = socket
      ) do
    my_addr =
      case name do
        "" -> [nil | addr]
        _ -> [name | addr]
      end

    my_addrs = String.split(String.trim(addrs), "\n")
    my_lists = String.split(String.trim(lists), "\n")
    archive_maildir = String.trim(maildir)
    orbit_api_key = String.trim(orbit_api_key)
    orbit_workspace = String.trim(workspace)

    archive_days =
      case Integer.parse(days) do
        {n, ""} when n > 0 -> n
        _ -> Configer.default(:archive_days)
      end

    sending_method =
      case sending_method do
        "local" -> :local
        "remote" -> :remote
        "sendgrid" -> :sendgrid
      end

    sending_data = %{
      sending_data
      | username: String.trim(username),
        password: String.trim(password),
        hostname: String.trim(hostname),
        api_key: String.trim(api_key)
    }

    # one more in the U/I
    boxes =
      0..length(boxes)
      |> Enum.map(fn i ->
        %{
          method: String.trim(config["method_#{i}"]),
          username: String.trim(config["username_#{i}"]),
          password: String.trim(config["password_#{i}"]),
          hostname: String.trim(config["hostname_#{i}"])
        }
      end)
      |> Enum.reject(fn
        %{method: ""} -> true
        _ -> false
      end)

    socket =
      cond do
        hd(my_addrs) != addr ->
          put_flash(
            socket,
            :error,
            "Your list of address should has your primary address as the first one"
          )

        to_string(archive_days) != days ->
          put_flash(
            socket,
            :error,
            "Days must be a positive integer"
          )

        sending_method == :remote &&
            (sending_data.username == "" || sending_data.password == "" ||
               sending_data.hostname == "") ->
          put_flash(
            socket,
            :error,
            "SMTP username, password and hostname must not be empty"
          )

        sending_method == :sendgrid && sending_data.api_key == "" ->
          put_flash(
            socket,
            :error,
            "Sendgrid API key must not be empty"
          )

        Enum.any?(boxes, &(&1.username == "" || &1.password == "" || &1.hostname == "")) ->
          put_flash(
            socket,
            :error,
            "POP3 username, password and hostname must not be empty"
          )

        true ->
          clear_flash(socket)
      end

    {
      :noreply,
      shadow(
        socket,
        my_addr: my_addr,
        my_addrs: my_addrs,
        my_lists: my_lists,
        archive_days: archive_days,
        archive_maildir: archive_maildir,
        orbit_api_key: orbit_api_key,
        orbit_workspace: orbit_workspace,
        sending_method: sending_method,
        sending_data: sending_data,
        reset_password: reset_password,
        remote_mail_boxes: boxes
      )
    }
  end

  def handle_event(
        "config_save",
        _params,
        %Socket{
          assigns: %{
            my_addr: my_addr,
            my_addrs: my_addrs,
            my_lists: my_lists,
            archive_days: archive_days,
            archive_maildir: archive_maildir,
            orbit_api_key: orbit_api_key,
            orbit_workspace: orbit_workspace,
            sending_method: sending_method,
            sending_data: sending_data,
            reset_password: reset_password,
            remote_mail_boxes: remote_mail_boxes
          }
        } = socket
      ) do
    Configer
    |> SelfConfiger.set_env(:my_address, my_addr)
    |> SelfConfiger.set_env(:my_addresses, my_addrs)
    |> SelfConfiger.set_env(:my_email_lists, my_lists)
    |> SelfConfiger.set_env(:archive_days, archive_days)
    |> SelfConfiger.set_env(:archive_maildir, archive_maildir)
    |> SelfConfiger.set_env(:orbit_api_key, orbit_api_key)
    |> SelfConfiger.set_env(:orbit_workspace, orbit_workspace)
    |> Configer.update_remote_mail_boxes(remote_mail_boxes)
    |> Configer.update_sending_method(sending_method, sending_data)

    close_action =
      case reset_password do
        "reset password" -> Routes.mail_path(Endpoint, :set_password)
        _ -> close_action(socket)
      end

    {
      :noreply,
      socket
      |> put_flash(:info, "Config saved")
      |> push_patch(to: close_action)
    }
  end

  def handle_event("close_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: close_action(socket))}
  end

  def handle_event(
        "backward_message",
        _params,
        %Socket{assigns: %{mail_client: mc, mail_docid: docid}} = socket
      ) do
    case MailClient.previous(mc, docid) do
      nil ->
        {:noreply, put_flash(socket, :warning, "Already at the beginning")}

      prev ->
        {
          :noreply,
          socket
          |> shadow(mail_docid: 0, mail_client: MailClient.close(mc, docid))
          |> push_patch(to: Routes.mail_path(Endpoint, :view, prev))
        }
    end
  end

  def handle_event(
        "forward_message",
        _params,
        %Socket{assigns: %{mail_client: mc, mail_docid: docid}} = socket
      ) do
    case MailClient.next(mc, docid) do
      nil ->
        {:noreply, put_flash(socket, :warning, "Already at the end")}

      next ->
        {
          :noreply,
          socket
          |> shadow(mail_docid: 0, mail_client: MailClient.close(mc, docid))
          |> push_patch(to: Routes.mail_path(Endpoint, :view, next))
        }
    end
  end

  def handle_event(
        "ack_attachment_chunk",
        %{"ref" => ref},
        %Socket{assigns: %{mail_docid: ref}} = socket
      ) do
    {
      :noreply,
      socket
      |> shadow(mail_chunk_outstanding: false)
      |> stream_attachments()
    }
  end

  def handle_event("ack_attachment_chunk", _params, socket) do
    # unsolicited ack
    {:noreply, socket}
  end

  def handle_event(
        "update_attachment_url",
        %{"ref" => ref, "seq" => seq, "url" => url},
        %Socket{assigns: %{mail_docid: ref, mail_attachment_metas: atts}} = socket
      ) do
    atts =
      Enum.map(atts, fn
        {^seq, name, type, size, offset, _url} -> {seq, name, type, size, offset, url}
        v -> v
      end)

    {:noreply, shadow(socket, mail_attachment_metas: atts)}
  end

  def handle_event("update_attachment_url", _params, socket) do
    # unsolicited ack
    {:noreply, socket}
  end

  def handle_event(
        "write_attach",
        %{"name" => name, "size" => size},
        %Socket{assigns: %{incoming_attachments: atts}} = socket
      ) do
    {
      :noreply,
      socket
      |> shadow(incoming_attachments: [{name, size} | atts])
      |> accept_streaming()
    }
  end

  def handle_event("attachment_chunk", %{"chunk" => chunk}, socket) do
    {
      :noreply,
      socket
      |> accept_chunk(chunk)
      |> accept_streaming()
    }
  end

  def handle_event(
        "drop_attachments",
        _params,
        %Socket{assigns: %{current_attachment: nil}} = socket
      ) do
    {:noreply, shadow(socket, write_attachments: [], info: "")}
  end

  def handle_event(
        "drop_attachments",
        _params,
        %Socket{assigns: %{current_attachment: {name, _size, offset, data}}} = socket
      ) do
    {
      :noreply,
      shadow(socket,
        write_attachments: [],
        current_attachment: {name, 0, offset, data},
        info: ""
      )
    }
  end

  def handle_event(
        "clear_flash",
        %{"key" => key},
        %Socket{assigns: %{mail_client: nil}} = socket
      ) do
    {:noreply, clear_flash(socket, key)}
  end

  def handle_event(
        "clear_flash",
        %{"key" => "info"},
        %Socket{assigns: %{live_action: :find, mail_client: mc}} = socket
      ) do
    {
      :noreply,
      socket
      |> clear_flash(:info)
      |> push_patch(to: Routes.mail_path(Endpoint, :find, mc.query))
    }
  end

  def handle_event("clear_flash", %{"key" => key}, socket) do
    {:noreply, clear_flash(socket, key)}
  end

  def handle_info(
        {:mail_part, ref, part},
        %Socket{
          assigns: %{
            mail_docid: ref,
            mail_attachments: attachments
          }
        } = socket
      ) do
    case MailClient.receive_part(part) do
      nil ->
        {:noreply, socket}

      :eof ->
        {:noreply, socket}

      {"", "text/plain", body} ->
        {
          :noreply,
          socket
          |> shadow(
            mail_text: body,
            mail_attachments: attachments ++ [{"", "text/plain", body}]
          )
          |> stream_attachments()
        }

      {name, type, body} ->
        {
          :noreply,
          socket
          |> shadow(mail_attachments: attachments ++ [{name, type, body}])
          |> stream_attachments()
        }
    end
  end

  def handle_info({:mail_part, _, _}, socket), do: {:noreply, socket}

  def handle_info(
        {:delete_message, docid},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    {:noreply, shadow(socket, mail_client: MailClient.set_meta(mc, docid, nil))}
  end

  def handle_info(
        {:mark_message, docid, mail},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    {:noreply, shadow(socket, mail_client: MailClient.set_meta(mc, docid, mail))}
  end

  def handle_info(
        {:unmark_message, docid, mail},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    {:noreply, shadow(socket, mail_client: MailClient.set_meta(mc, docid, mail))}
  end

  def handle_info(
        {:archive_message, docid, mail},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    {:noreply, shadow(socket, mail_client: MailClient.set_meta(mc, docid, mail))}
  end

  def handle_info(
        {:seen_message, docid, mail},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    {:noreply, shadow(socket, mail_client: MailClient.set_meta(mc, docid, mail))}
  end

  def handle_info(:new_mail, %Socket{assigns: %{mail_client: nil}} = socket) do
    {:noreply, put_flash(socket, :info, "You've got new mails")}
  end

  def handle_info(:new_mail, %Socket{assigns: %{mail_client: mc}} = socket) do
    {
      :noreply,
      socket
      |> put_flash(:info, "You've got new mails")
      |> shadow(mail_client: MailClient.set_stale(mc))
    }
  end

  def handle_info(
        {:draft_update, subject, recipients, body},
        %Socket{assigns: %{live_action: :draft}} = socket
      ) do
    {
      :noreply,
      shadow(socket,
        recipients: recipients || MailClient.default_recipients(),
        info: subject || "",
        subject: subject || "",
        write_text: body || ""
      )
    }
  end

  def handle_info({:draft_update, subject, recipients, body}, socket) do
    {
      :noreply,
      shadow(socket,
        recipients: recipients || MailClient.default_recipients(),
        subject: subject || "",
        write_text: body || ""
      )
    }
  end

  defp shadow(%Socket{assigns: %{token: token}} = socket, keyword) do
    Shadow.assign(token, keyword)
    assign(socket, keyword)
  end

  defp restore(%Socket{assigns: %{token: token} = assigns} = socket) do
    # load everything from the shadow, except the ones that depends on client state
    data =
      token
      |> Shadow.get()
      |> Map.delete(:mail_docid)
      |> Map.delete(:mail_chunk_outstanding)
      |> Map.delete(:mail_attachments)
      |> Map.delete(:mail_attachment_offset)
      |> Map.delete(:mail_attachment_metas)

    %{socket | assigns: Map.merge(assigns, data)}
  end

  defp close_action(%Socket{assigns: %{mail_docid: 0, mail_client: nil}}) do
    Routes.mail_path(Endpoint, :find, @default_query)
  end

  defp close_action(%Socket{assigns: %{mail_docid: 0, mail_client: mc}}) do
    Routes.mail_path(Endpoint, :find, mc.query)
  end

  defp close_action(%Socket{assigns: %{mail_docid: docid}}) do
    Routes.mail_path(Endpoint, :view, docid)
  end

  defp fetch_token(socket, %{"token" => token}) do
    with {:ok, key} <- Base.url_decode64(token),
         true <- Guardian.valid_token?(key) do
      socket
      |> shadow(auth: :logged_in, token: key)
      |> restore()
    else
      _ ->
        shadow(socket, auth: :logged_out, token: nil)
    end
  end

  defp fetch_token(socket, _), do: shadow(socket, auth: :logged_out, token: nil)

  defp fetch_tz_offset(socket, %{"timezoneOffset" => offset}) do
    shadow(socket, tz_offset: offset)
  end

  defp fetch_tz_offset(socket, _), do: socket

  defp fetch_locale(socket, %{"language" => language}) do
    case language |> language_to_locale() |> validate_locale() do
      nil -> :ok
      locale -> Gettext.put_locale(LivWeb.Gettext, locale)
    end

    socket
  end

  defp fetch_locale(socket, _) do
    Gettext.put_locale(LivWeb.Gettext, "en")
    socket
  end

  defp language_to_locale(language) do
    String.replace(language, "-", "_", global: false)
  end

  defp validate_locale(nil), do: nil

  defp validate_locale(locale) do
    supported_locales = Gettext.known_locales(LivWeb.Gettext)

    case String.split(locale, "_") do
      [language, _] ->
        Enum.find([locale, language], fn locale ->
          locale in supported_locales
        end)

      [^locale] ->
        if locale in supported_locales do
          locale
        else
          nil
        end
    end
  end

  defp mail_not_found(socket, mc) do
    query = if mc, do: mc.query, else: @default_query

    socket
    |> put_flash(:error, "Mail not found")
    |> shadow(
      info: "Mail not found",
      home_link: Routes.mail_path(Endpoint, :find, query),
      page_title: "Mail not found",
      buttons: [
        {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
        {:patch, "\u{23F3}", Routes.mail_path(Endpoint, :boomerang), true},
        {:button, "\u{25C0}", "backward_message", true},
        {:button, "\u{25B6}", "forward_message", true}
      ]
    )
  end

  defp mail_unchanged(socket, mc, docid) do
    meta = MailClient.mail_meta(mc, docid)

    socket
    |> shadow(
      info: "",
      home_link: Routes.mail_path(Endpoint, :find, mc.query),
      page_title: meta.subject,
      buttons: [
        {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
        {:patch, "\u{23F3}", Routes.mail_path(Endpoint, :boomerang), false},
        {:button, "\u{25C0}", "backward_message", MailClient.is_first(mc, docid)},
        {:button, "\u{25B6}", "forward_message", MailClient.is_last(mc, docid)}
      ]
    )
  end

  defp mail_found(socket, mc, docid) do
    meta = MailClient.mail_meta(mc, docid)

    socket
    |> push_event("clear_attachments", %{})
    |> shadow(
      mail_meta: meta,
      mail_text: "",
      mail_chunk_outstanding: false,
      mail_attachments: [],
      mail_attachment_offset: 0,
      mail_attachment_metas: [],
      mail_docid: docid,
      info: "",
      home_link: Routes.mail_path(Endpoint, :find, mc.query),
      page_title: meta.subject,
      mail_client: mc,
      buttons: [
        {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
        {:patch, "\u{23F3}", Routes.mail_path(Endpoint, :boomerang), false},
        {:button, "\u{25C0}", "backward_message", MailClient.is_first(mc, docid)},
        {:button, "\u{25B6}", "forward_message", MailClient.is_last(mc, docid)}
      ]
    )
  end

  defp stream_attachments(
         %Socket{
           assigns: %{
             mail_chunk_outstanding: true
           }
         } = socket
       ) do
    socket
  end

  defp stream_attachments(
         %Socket{
           assigns: %{
             mail_attachments: []
           }
         } = socket
       ) do
    socket
  end

  defp stream_attachments(
         %Socket{
           assigns: %{
             mail_docid: ref,
             mail_attachments: [{name, <<"text/", _::binary>> = type, content} | tail],
             mail_attachment_metas: atts,
             mail_attachment_offset: 0
           }
         } = socket
       )
       when byte_size(content) <= @chunk_size do
    seq = Enum.count(atts)

    socket
    |> push_event("attachment_start", %{type: type})
    |> push_event("attachment_chunk", %{ref: ref, chunk: content})
    |> push_event("attachment_end", %{ref: ref, seq: seq, name: name})
    |> shadow(
      mail_chunk_outstanding: true,
      mail_attachments: tail,
      mail_attachment_metas: atts ++ [{seq, name, type, byte_size(content), 0, ""}]
    )
  end

  defp stream_attachments(
         %Socket{
           assigns: %{
             mail_docid: ref,
             mail_attachments: [{name, <<"text/", _::binary>> = type, content} | tail] = list,
             mail_attachment_metas: atts,
             mail_attachment_offset: offset
           }
         } = socket
       ) do
    content_size = String.length(content)
    first? = offset == 0
    atts = unless first?, do: Enum.drop(atts, -1), else: atts
    push_size = min(content_size - offset, @chunk_size >>> 2)
    chunk = String.slice(content, offset, push_size)
    seq = Enum.count(atts)
    atts = atts ++ [{seq, name, type, content_size, offset, ""}]
    offset = offset + push_size
    last? = offset == content_size
    atts_in = if last?, do: tail, else: list
    offset = if last?, do: 0, else: offset

    socket
    |> maybe_push(first?, "attachment_start", %{type: type})
    |> push_event("attachment_chunk", %{ref: ref, chunk: chunk})
    |> maybe_push(last?, "attachment_end", %{ref: ref, seq: seq, name: name})
    |> shadow(
      mail_chunk_outstanding: true,
      mail_attachments: atts_in,
      mail_attachment_offset: offset,
      mail_attachment_metas: atts
    )
  end

  defp stream_attachments(
         %Socket{
           assigns: %{
             mail_docid: ref,
             mail_attachments: [{name, type, content} | tail],
             mail_attachment_metas: atts,
             mail_attachment_offset: 0
           }
         } = socket
       )
       when byte_size(content) <= @chunk_size do
    seq = Enum.count(atts)

    socket
    |> push_event("attachment_start", %{type: type})
    |> push_event("attachment_chunk", %{ref: ref, chunk: Base.encode64(content)})
    |> push_event("attachment_end", %{ref: ref, seq: seq, name: name})
    |> shadow(
      mail_chunk_outstanding: true,
      mail_attachments: tail,
      mail_attachment_metas: atts ++ [{seq, name, type, byte_size(content), 0, ""}]
    )
  end

  defp stream_attachments(
         %Socket{
           assigns: %{
             mail_docid: ref,
             mail_attachments: [{name, type, content} | tail] = list,
             mail_attachment_metas: atts,
             mail_attachment_offset: offset
           }
         } = socket
       ) do
    content_size = byte_size(content)
    first? = offset == 0
    atts = unless first?, do: Enum.drop(atts, -1), else: atts
    push_size = min(content_size - offset, @chunk_size)
    chunk = Base.encode64(binary_part(content, offset, push_size))
    seq = Enum.count(atts)
    atts = atts ++ [{seq, name, type, content_size, offset, ""}]
    offset = offset + push_size
    last? = offset == content_size
    atts_in = if last?, do: tail, else: list
    offset = if last?, do: 0, else: offset

    socket
    |> maybe_push(first?, "attachment_start", %{type: type})
    |> push_event("attachment_chunk", %{ref: ref, chunk: chunk})
    |> maybe_push(last?, "attachment_end", %{ref: ref, seq: seq, name: name})
    |> shadow(
      mail_chunk_outstanding: true,
      mail_attachments: atts_in,
      mail_attachment_offset: offset,
      mail_attachment_metas: atts
    )
  end

  defp maybe_push(socket, true, name, payload), do: push_event(socket, name, payload)
  defp maybe_push(socket, false, _, _), do: socket

  defp accept_chunk(
         %Socket{
           assigns: %{current_attachment: {_name, 0, _offset, _data}, write_attachments: atts}
         } = socket,
         _chunk
       ) do
    shadow(socket,
      current_attachment: nil,
      write_chunk_outstanding: false,
      info: attachments_info(atts, 0)
    )
  end

  defp accept_chunk(
         %Socket{
           assigns: %{current_attachment: {name, size, offset, data}, write_attachments: atts}
         } = socket,
         chunk
       ) do
    chunk = Base.decode64!(chunk)
    offset = offset + byte_size(chunk)

    data =
      cond do
        offset > size -> raise("Excessive data received in streaming")
        offset == size -> Enum.reverse([chunk | data])
        true -> [chunk | data]
      end

    if offset == size do
      atts = [{name, size, data} | atts]

      shadow(socket,
        info: attachments_info(atts, 0),
        write_attachments: atts,
        current_attachment: nil,
        write_chunk_outstanding: false
      )
    else
      shadow(socket,
        info: attachments_info(atts, offset),
        current_attachment: {name, size, offset, data},
        write_chunk_outstanding: false
      )
    end
  end

  defp attachments_info(attachments, offset) do
    {count, bytes} =
      Enum.reduce(attachments, {0, 0}, fn {_name, s, _data}, {c, b} -> {c + 1, b + s} end)

    case {count, bytes, offset} do
      {0, 0, 0} -> ""
      {_, _, 0} -> "#{count} files/#{div(bytes, 1024)}KB"
      _ -> "#{count + 1} files/#{div(bytes + offset, 1024)}KB"
    end
  end

  defp accept_streaming(%Socket{assigns: %{write_chunk_outstanding: true}} = socket) do
    socket
  end

  defp accept_streaming(
         %Socket{assigns: %{current_attachment: nil, incoming_attachments: []}} = socket
       ) do
    socket
  end

  defp accept_streaming(
         %Socket{assigns: %{current_attachment: nil, incoming_attachments: atts}} = socket
       ) do
    {atts, [{name, size}]} = Enum.split(atts, -1)

    socket
    |> shadow(
      current_attachment: {name, size, 0, []},
      incoming_attachments: atts,
      write_chunk_outstanding: true
    )
    |> push_event("read_attachment", %{name: name, offset: 0})
  end

  defp accept_streaming(
         %Socket{assigns: %{current_attachment: {name, _size, offset, _data}}} = socket
       ) do
    socket
    |> shadow(write_chunk_outstanding: true)
    |> push_event("read_attachment", %{name: name, offset: offset})
  end

  defp sort_address_book(book, sorted_by, desc) do
    Enum.sort(book, fn a, b ->
      case {sorted_by, desc} do
        {:from, true} -> a.name > b.name || (a.name == b.name && a.addr >= b.addr)
        {:from, false} -> a.name < b.name || (a.name == b.name && a.addr <= b.addr)
        {:first, true} -> a.first >= b.first
        {:first, false} -> a.first <= b.first
        {:last, true} -> a.last >= b.last
        {:last, false} -> a.last <= b.last
        {:count, true} -> a.count >= b.count
        {:count, false} -> a.count <= b.count
      end
    end)
  end
end
