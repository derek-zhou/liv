defmodule LivWeb.MailLive do
  use Surface.LiveView
  require Logger

  @default_query "maildir:/"
  @chunk_size 65536

  alias Liv.{Configer, MailClient, AddressVault, DraftServer, DelayMarker}

  alias LivWeb.{
    Main,
    Find,
    Search,
    View,
    Print,
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

  # client side state
  # nil, logged_in, logged_out
  data auth, :atom, default: nil
  data tz_offset, :integer, default: 0
  data recover_query, :string, default: @default_query

  # the mail client app state
  data mail_client, :map, default: nil

  # new mail count since last checking
  data new_mail_count, :integer, default: 0

  # for login
  data password_hash, :string, default: ""
  data saved_password, :string, default: ""
  data password_prompt, :string, default: "Enter your password: "
  data saved_path, :string, default: "/"

  # for the header
  data info, :string, default: "Loading..."
  data buttons, :list, default: []
  data home_link, :string, default: "#"

  # for finder
  data list_mails, :map, default: %{}
  data list_tree, :tuple, default: nil

  # if this is true, we should return to viewer instead of finder
  data mail_opened, :boolean, default: false

  # for the viewer
  data mail_attachments, :list, default: []
  data mail_attachment_offset, :integer, default: 0
  data mail_attachment_metas, :list, default: []
  data mail_chunk_outstanding, :boolean, default: false
  data mail_meta, :any, default: nil
  data mail_content, :tuple, default: {:text, ""}
  data mail_text, :string, default: ""

  # to refer back in later 
  data last_query, :string, default: ""

  # for search
  data default_query, :string, default: @default_query

  data query_examples, :list,
    default: [
      {"The inbox", "maildir:/"},
      {"Unread mails", "flag:unread"},
      {"Last 7 days", "date:7d..now flag:replied"}
    ]

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
  data compose_debounce, :integer, default: 1000

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
          |> fetch_recover_query(values)
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
      |> assign(
        auth: :logged_out,
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
          |> assign(auth: :logged_in, saved_path: uri.path)
          |> push_patch(to: Routes.mail_path(Endpoint, :set_password))
        }

      hash ->
        {
          :noreply,
          socket
          |> assign(password_hash: hash, saved_path: uri.path)
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
      |> assign(
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
            last_query: last_query,
            new_mail_count: count
          }
        } = socket
      ) do
    mc = MailClient.close(mc)

    mc =
      cond do
        count > 0 -> MailClient.new_search(query)
        mc && query == last_query -> mc
        true -> MailClient.new_search(query)
      end

    {
      :noreply,
      socket
      |> push_event("set_value", %{key: "recoverQuery", value: query})
      |> assign(
        info: "#{MailClient.unread_count(mc)} unread/#{MailClient.mail_count(mc)}",
        home_link: Routes.mail_path(Endpoint, :find, query),
        mail_opened: false,
        page_title: query,
        list_mails: MailClient.mails_of(mc),
        list_tree: MailClient.tree_of(mc),
        mail_client: mc,
        last_query: query,
        new_mail_count: 0,
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
            recover_query: query,
            mail_client: nil
          }
        } = socket
      ) do
    case Integer.parse(docid) do
      {docid, ""} ->
        {mc, query} =
          case query do
            "" ->
              case MailClient.open(nil, docid) do
                nil -> {nil, nil}
                mc -> {mc, nil}
              end

            _ ->
              mc = MailClient.new_search(query)

              case MailClient.mail_meta(mc, docid) do
                nil ->
                  case MailClient.open(nil, docid) do
                    nil -> {nil, nil}
                    mc -> {mc, nil}
                  end

                _ ->
                  {MailClient.open(mc, docid), query}
              end
          end

        case mc do
          nil ->
            {
              :noreply,
              socket
              |> put_flash(:error, "Mail not found")
              |> assign(
                info: "Mail not found",
                home_link: Routes.mail_path(Endpoint, :find, @default_query),
                page_title: "Mail not found",
                buttons: [
                  {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
                  {:patch, "\u{23F3}", Routes.mail_path(Endpoint, :boomerang), true},
                  {:patch, "\u{1F5A8}", Routes.mail_path(Endpoint, :print), true},
                  {:button, "\u{25C0}", "backward_message", true},
                  {:button, "\u{25B6}", "forward_message", true}
                ]
              )
            }

          _ ->
            meta = MailClient.mail_meta(mc, docid)
            query = query || MailClient.solo_query(mc)

            {
              :noreply,
              socket
              |> open_mail(meta)
              |> assign(
                info: "",
                home_link: Routes.mail_path(Endpoint, :find, query),
                page_title: meta.subject,
                mail_client: mc,
                last_query: query,
                docid: docid,
                buttons: [
                  {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
                  {:patch, "\u{23F3}", Routes.mail_path(Endpoint, :boomerang), false},
                  {:patch, "\u{1F5A8}", Routes.mail_path(Endpoint, :print), false},
                  {:button, "\u{25C0}", "backward_message", MailClient.is_first(mc, docid)},
                  {:button, "\u{25B6}", "forward_message", MailClient.is_last(mc, docid)}
                ]
              )
            }
        end

      _ ->
        {
          :noreply,
          socket
          |> put_flash(:error, "Illegal docid")
          |> assign(
            info: "Mail not found",
            home_link: Routes.mail_path(Endpoint, :find, @default_query),
            page_title: "Mail not found",
            buttons: [
              {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
              {:patch, "\u{23F3}", Routes.mail_path(Endpoint, :boomerang), true},
              {:patch, "\u{1F5A8}", Routes.mail_path(Endpoint, :print), true},
              {:button, "\u{25C0}", "backward_message", true},
              {:button, "\u{25B6}", "forward_message", true}
            ]
          )
        }
    end
  end

  def handle_params(
        _params,
        _url,
        %Socket{
          assigns: %{
            live_action: :view,
            mail_opened: true,
            last_query: query,
            mail_client: mc
          }
        } = socket
      ) do
    meta = MailClient.mail_meta(mc, mc.docid)

    {
      :noreply,
      socket
      |> assign(
        info: "",
        home_link: Routes.mail_path(Endpoint, :find, query),
        page_title: meta.subject,
        docid: mc.docid,
        buttons: [
          {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
          {:patch, "\u{23F3}", Routes.mail_path(Endpoint, :boomerang), false},
          {:patch, "\u{1F5A8}", Routes.mail_path(Endpoint, :print), false},
          {:button, "\u{25C0}", "backward_message", MailClient.is_first(mc, mc.docid)},
          {:button, "\u{25B6}", "forward_message", MailClient.is_last(mc, mc.docid)}
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
            last_query: query
          }
        } = socket
      ) do
    case Integer.parse(docid) do
      {docid, ""} ->
        mc = MailClient.open(mc, docid)

        case MailClient.mail_meta(mc, docid) do
          nil ->
            {
              :noreply,
              socket
              |> put_flash(:error, "Mail not found")
              |> assign(
                info: "",
                home_link: Routes.mail_path(Endpoint, :find, query),
                page_title: "Mail not found",
                buttons: [
                  {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
                  {:patch, "\u{23F3}", Routes.mail_path(Endpoint, :boomerang), true},
                  {:patch, "\u{1F5A8}", Routes.mail_path(Endpoint, :print), true},
                  {:button, "\u{25C0}", "backward_message", true},
                  {:button, "\u{25B6}", "forward_message", true}
                ]
              )
            }

          meta ->
            {
              :noreply,
              socket
              |> open_mail(meta)
              |> assign(
                info: "",
                home_link: Routes.mail_path(Endpoint, :find, query),
                page_title: meta.subject,
                mail_client: mc,
                docid: docid,
                buttons: [
                  {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
                  {:patch, "\u{23F3}", Routes.mail_path(Endpoint, :boomerang), false},
                  {:patch, "\u{1F5A8}", Routes.mail_path(Endpoint, :print), false},
                  {:button, "\u{25C0}", "backward_message", MailClient.is_first(mc, docid)},
                  {:button, "\u{25B6}", "forward_message", MailClient.is_last(mc, docid)}
                ]
              )
            }
        end

      _ ->
        {
          :noreply,
          socket
          |> put_flash(:error, "Illegal docid")
          |> assign(
            info: "",
            home_link: Routes.mail_path(Endpoint, :find, query),
            page_title: "Mail not found",
            buttons: [
              {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
              {:patch, "\u{23F3}", Routes.mail_path(Endpoint, :boomerang), true},
              {:patch, "\u{1F5A8}", Routes.mail_path(Endpoint, :print), true},
              {:button, "\u{25C0}", "backward_message", true},
              {:button, "\u{25B6}", "forward_message", true}
            ]
          )
        }
    end
  end

  def handle_params(
        _params,
        _url,
        %Socket{
          assigns: %{
            live_action: :print,
            mail_opened: true
          }
        } = socket
      ) do
    {
      :noreply,
      socket
      |> assign(
        info: "Print",
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
            last_query: query,
            mail_opened: opened,
            mail_client: mc
          }
        } = socket
      ) do
    examples =
      case opened do
        true ->
          [
            {"Same thread", MailClient.solo_query(mc)},
            {"Same sender", MailClient.from_query(mc)},
            {"Last query", query}
          ]

        false ->
          [
            {"The inbox", "maildir:/"},
            {"Unread mails", "flag:unread"},
            {"Last 7 days", "date:7d..now flag:replied"}
          ]
      end

    MailClient.snooze()

    {
      :noreply,
      socket
      |> assign(
        default_query: examples |> hd() |> elem(1),
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
      |> assign(
        page_title: "Config",
        info: "Config",
        my_addr: Configer.default(:my_address),
        my_addrs: Configer.default(:my_addresses),
        my_lists: Configer.default(:my_email_lists),
        archive_days: Configer.default(:archive_days),
        compose_debounce: Configer.default(:compose_debounce),
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
      |> assign(
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
      |> assign(
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
        %Socket{assigns: %{live_action: :write, mail_opened: false}} = socket
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
      |> assign(
        page_title: "Write",
        info: "",
        home_link: "#",
        recipients: recipients,
        subject: subject || d_subject || "",
        write_text: MailClient.quoted_text(nil, text) || d_text || "",
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
        %Socket{assigns: %{live_action: :write, mail_client: mc, mail_text: text}} = socket
      ) do
    {msgid, refs} =
      case MailClient.mail_meta(mc, mc.docid) do
        %{msgid: msgid, references: refs} -> {msgid, refs}
        _ -> {nil, []}
      end

    {
      :noreply,
      socket
      |> assign(
        page_title: "Write",
        info: "",
        home_link: "#",
        recipients: MailClient.default_recipients(mc, to),
        subject: MailClient.reply_subject(mc),
        write_text: MailClient.quoted_text(mc, text),
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
      |> assign(
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
      |> assign(
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
      assign(socket,
        info: "Boomerang a Mail",
        home_link: "#",
        page_title: "Boomerang a Mail",
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
            recover_query: query
          }
        } = socket
      ) do
    query = query || @default_query
    {:noreply, push_patch(socket, to: Routes.mail_path(Endpoint, :find, query))}
  end

  def handle_event(
        "boomerang_submit",
        %{"hours" => hours},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    DelayMarker.flag(mc.docid, String.to_integer(hours) * 3600)
    {:noreply, push_patch(socket, to: close_action(socket))}
  end

  def handle_event("get_value", values, socket) do
    {
      :noreply,
      socket
      |> fetch_token(values)
      |> fetch_tz_offset(values)
      |> fetch_locale(values)
      |> fetch_recover_query(values)
    }
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
      |> assign(
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
      |> assign(password_hash: hash)
      |> push_patch(to: path)
    }
  end

  def handle_event("pw_submit", _, %Socket{assigns: %{password_hash: nil}} = socket) do
    {
      :noreply,
      socket
      |> put_flash(:error, "Passwords do not match")
      |> assign(
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
        {
          :noreply,
          socket
          |> clear_flash()
          |> push_event("set_value", %{key: "token", value: Guardian.build_token()})
          |> assign(auth: :logged_in)
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
      |> assign(mail_client: nil)
      |> push_patch(to: Routes.mail_path(Endpoint, :find, query))
    }
  end

  def handle_event("pick_search_example", %{"query" => query}, socket) do
    {:noreply, assign(socket, default_query: query)}
  end

  def handle_event(
        "delete_address",
        %{"address" => addr},
        %Socket{assigns: %{address_book: book}} = socket
      ) do
    AddressVault.remove(addr)
    book = Enum.reject(book, fn entry -> entry.addr == addr end)

    {:noreply,
     assign(socket,
       info: "#{Enum.count(book)} correspondents",
       address_book: book
     )}
  end

  def handle_event(
        "write_change",
        %{"_target" => [target | _], "subject" => subject, "text" => text} = mail,
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
      assign(socket,
        recipients: recipients,
        subject: subject,
        addr_options: completion_list,
        write_text: text
      )
    }
  end

  def handle_event(
        "write_recover",
        %{"subject" => subject, "text" => text} = mail,
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
      assign(socket,
        recipients: recipients,
        subject: subject,
        write_text: text,
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
          |> assign(
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
      |> assign(
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
          "compose_debounce" => miliseconds,
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

    compose_debounce =
      case Integer.parse(miliseconds) do
        {n, ""} when n > 0 -> n
        _ -> Configer.default(:compose_debounce)
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

        to_string(compose_debounce) != miliseconds ->
          put_flash(
            socket,
            :error,
            "Miliseconds must be a positive integer"
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
      assign(
        socket,
        my_addr: my_addr,
        my_addrs: my_addrs,
        my_lists: my_lists,
        archive_days: archive_days,
        archive_maildir: archive_maildir,
        compose_debounce: compose_debounce,
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
            compose_debounce: compose_debounce,
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
    |> SelfConfiger.set_env(:compose_debounce, compose_debounce)
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
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    case MailClient.previous(mc, mc.docid) do
      nil ->
        {:noreply, put_flash(socket, :warning, "Already at the beginning")}

      prev ->
        {
          :noreply,
          socket
          |> assign(mail_opened: false)
          |> push_patch(to: Routes.mail_path(Endpoint, :view, prev))
        }
    end
  end

  def handle_event(
        "forward_message",
        _params,
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    case MailClient.next(mc, mc.docid) do
      nil ->
        {:noreply, put_flash(socket, :warning, "Already at the end")}

      next ->
        {
          :noreply,
          socket
          |> assign(mail_opened: false)
          |> push_patch(to: Routes.mail_path(Endpoint, :view, next))
        }
    end
  end

  def handle_event("ack_attachment_chunk", params, socket) do
    socket =
      case Map.get(params, "url") do
        nil -> socket
        url -> append_attachment_url(socket, url)
      end

    {
      :noreply,
      socket
      |> assign(mail_chunk_outstanding: false)
      |> stream_attachments()
    }
  end

  def handle_event(
        "write_attach",
        %{"name" => name, "size" => size},
        %Socket{assigns: %{incoming_attachments: atts}} = socket
      ) do
    {
      :noreply,
      socket
      |> assign(incoming_attachments: [{name, size} | atts])
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
    {:noreply, assign(socket, write_attachments: [], info: "")}
  end

  def handle_event(
        "drop_attachments",
        _params,
        %Socket{assigns: %{current_attachment: {name, _size, offset, data}}} = socket
      ) do
    {
      :noreply,
      assign(socket, write_attachments: [], current_attachment: {name, 0, offset, data}, info: "")
    }
  end

  def handle_event(
        "clear_flash",
        %{"key" => key},
        %Socket{assigns: %{new_mail_count: 0}} = socket
      ) do
    {:noreply, clear_flash(socket, key)}
  end

  def handle_event(
        "clear_flash",
        %{"key" => "info"},
        %Socket{assigns: %{live_action: :find, last_query: query}} = socket
      ) do
    {
      :noreply,
      socket
      |> clear_flash(:info)
      |> push_patch(to: Routes.mail_path(Endpoint, :find, query))
    }
  end

  def handle_event("clear_flash", %{"key" => key}, socket) do
    {:noreply, clear_flash(socket, key)}
  end

  def handle_info(
        {:mail_part, ref, part},
        %Socket{
          assigns: %{
            mail_client: mc,
            mail_text: text,
            mail_content: {type, html},
            mail_attachments: attachments
          }
        } = socket
      ) do
    case MailClient.receive_part(mc, ref, part) do
      nil ->
        {:noreply, socket}

      :eof ->
        # if we have not seen a html part by now, promote the text
        case {text, type, html} do
          {"", _, _} -> {:noreply, socket}
          {_, :text, ""} -> {:noreply, assign(socket, mail_content: {:text, text})}
          _ -> {:noreply, socket}
        end

      {:text, body} ->
        case text do
          "" -> {:noreply, assign(socket, mail_text: body)}
          _ -> {:noreply, socket}
        end

      {:html, body} ->
        case {type, html} do
          {:text, ""} ->
            {:noreply, assign(socket, mail_content: {:html, String.trim_leading(body)})}

          _ ->
            {:noreply, socket}
        end

      {:attachment, name, type, body} ->
        # if we have not seen a html part by now, promote the text
        socket =
          case {text, type, html} do
            {"", _, _} -> socket
            {_, :text, ""} -> assign(socket, mail_content: {:text, text})
            _ -> socket
          end

        {
          :noreply,
          socket
          |> assign(mail_attachments: attachments ++ [{name, type, body}])
          |> stream_attachments()
        }
    end
  end

  def handle_info(
        {:delete_message, docid},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    {:noreply, assign(socket, mail_client: MailClient.set_meta(mc, docid, nil))}
  end

  def handle_info(
        {:mark_message, docid, mail},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    {:noreply, assign(socket, mail_client: MailClient.set_meta(mc, docid, mail))}
  end

  def handle_info(
        {:unmark_message, docid, mail},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    {:noreply, assign(socket, mail_client: MailClient.set_meta(mc, docid, mail))}
  end

  def handle_info(
        {:archive_message, docid, mail},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    {:noreply, assign(socket, mail_client: MailClient.set_meta(mc, docid, mail))}
  end

  def handle_info(
        {:seen_message, docid, mail},
        %Socket{assigns: %{mail_client: mc}} = socket
      ) do
    {:noreply, assign(socket, mail_client: MailClient.set_meta(mc, docid, mail))}
  end

  def handle_info(:new_mail, %Socket{assigns: %{new_mail_count: c}} = socket) do
    c = c + 1

    {
      :noreply,
      socket
      |> put_flash(:info, "You've got #{c} new mails")
      |> assign(new_mail_count: c)
    }
  end

  def handle_info(
        {:draft_update, subject, recipients, body},
        %Socket{assigns: %{live_action: :draft}} = socket
      ) do
    {
      :noreply,
      assign(socket,
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
      assign(socket,
        recipients: recipients || MailClient.default_recipients(),
        subject: subject || "",
        write_text: body || ""
      )
    }
  end

  defp close_action(%Socket{assigns: %{mail_client: mc, mail_opened: true}}) do
    Routes.mail_path(Endpoint, :view, mc.docid)
  end

  defp close_action(%Socket{assigns: %{last_query: ""}}) do
    Routes.mail_path(Endpoint, :find, @default_query)
  end

  defp close_action(%Socket{assigns: %{last_query: query}}) do
    Routes.mail_path(Endpoint, :find, query)
  end

  defp fetch_token(socket, %{"token" => token}) do
    assign(socket,
      auth:
        case Guardian.decode_token(token) do
          nil -> :logged_out
          _ -> :logged_in
        end
    )
  end

  defp fetch_token(socket, _), do: assign(socket, auth: :logged_out)

  defp fetch_tz_offset(socket, %{"timezoneOffset" => offset}) do
    assign(socket, tz_offset: offset)
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

  defp fetch_recover_query(socket, %{"recoverQuery" => query}) do
    assign(socket, recover_query: query)
  end

  defp fetch_recover_query(socket, _), do: assign(socket, recover_query: @default_query)

  defp open_mail(socket, meta) do
    socket
    |> push_event("clear_attachment", %{})
    |> assign(
      mail_opened: true,
      mail_meta: meta,
      mail_text: "",
      mail_content: {:text, ""},
      mail_attachments: [],
      mail_attachment_offset: 0,
      mail_attachment_metas: []
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
             mail_attachments: [{name, type, content} | tail] = list,
             mail_attachment_metas: atts,
             mail_attachment_offset: offset
           }
         } = socket
       ) do
    content_size = byte_size(content)

    {atts, first} =
      cond do
        offset == 0 -> {atts, true}
        true -> {Enum.drop(atts, -1), false}
      end

    push_size =
      cond do
        content_size - offset <= @chunk_size -> content_size - offset
        true -> @chunk_size
      end

    atts = atts ++ [{name, type, content_size, offset, ""}]
    chunk = Base.encode64(binary_part(content, offset, push_size))
    offset = offset + push_size

    {atts_in, offset, last} =
      cond do
        offset == content_size -> {tail, 0, true}
        true -> {list, offset, false}
      end

    socket
    |> push_event("attachment_chunk", %{first: first, last: last, chunk: chunk})
    |> assign(
      mail_chunk_outstanding: true,
      mail_attachments: atts_in,
      mail_attachment_offset: offset,
      mail_attachment_metas: atts
    )
  end

  defp append_attachment_url(
         %Socket{assigns: %{mail_attachment_metas: []}} = socket,
         _url
       ) do
    socket
  end

  defp append_attachment_url(
         %Socket{assigns: %{mail_attachment_metas: atts}} = socket,
         url
       ) do
    {atts, [{name, type, size, _offset, _url}]} = Enum.split(atts, -1)
    atts = atts ++ [{name, type, size, size, url}]
    assign(socket, mail_attachment_metas: atts)
  end

  defp accept_chunk(
         %Socket{
           assigns: %{current_attachment: {_name, 0, _offset, _data}, write_attachments: atts}
         } = socket,
         _chunk
       ) do
    assign(socket,
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
        offset > size ->
          raise("Excessive data received in streaming")

        offset == size ->
          Enum.reverse([chunk | data])

        true ->
          [chunk | data]
      end

    cond do
      offset == size ->
        atts = [{name, size, data} | atts]

        assign(socket,
          info: attachments_info(atts, 0),
          write_attachments: atts,
          current_attachment: nil,
          write_chunk_outstanding: false
        )

      true ->
        assign(socket,
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
    |> assign(
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
    |> assign(write_chunk_outstanding: true)
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
