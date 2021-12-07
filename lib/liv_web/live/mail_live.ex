defmodule LivWeb.MailLive do
  use Surface.LiveView
  require Logger

  @default_query "maildir:/"
  @chunk_size 65536

  alias Liv.{Configer, MailClient, AddressVault}
  alias LivWeb.{Main, Find, Search, View, Login, Guardian, Write, Config, Draft}
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

  # for login
  data password_hash, :string, default: ""
  data saved_password, :string, default: ""
  data password_prompt, :string, default: "Enter your password: "

  # for the header
  data info, :string, default: "Loading..."
  data buttons, :list, default: []

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
  data mail_meta, :map, default: nil
  data mail_content, :tuple, default: {:text, ""}
  data mail_text, :string, default: ""

  # to refer back in later 
  data last_query, :string, default: ""
  data default_query, :string, default: ""

  # for write
  data recipients, :list, default: []
  data addr_options, :list, default: []
  data subject, :string, default: ""
  data write_text, :string, default: ""
  data preview_html, :string, default: ""
  data write_attachments, :list, default: []
  data current_attachment, :tuple, default: nil
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

  def mount(_params, _session, socket) do
    cond do
      connected?(socket) ->
        MailClient.snooze()
        PubSub.subscribe(Liv.PubSub, "messages")
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
        page_title: "Login as #{user}",
        password_hash: Application.get_env(:liv, :password_hash),
        password_prompt: "Enter your password: ",
        info: "Login as #{user}",
        buttons: []
      )
    }
  end

  def handle_params(_params, _url, %Socket{assigns: %{auth: :logged_out}} = socket) do
    case Application.get_env(:liv, :password_hash) do
      nil ->
        # temporarily log user in to set the password
        {
          :noreply,
          socket
          |> assign(auth: :logged_in)
          |> push_patch(to: Routes.mail_path(Endpoint, :set_password))
        }

      hash ->
        {
          :noreply,
          socket
          |> assign(password_hash: hash)
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
        %Socket{assigns: %{live_action: :find, mail_client: mc, last_query: last_query}} = socket
      ) do
    mc =
      cond do
        mc && query == last_query -> MailClient.seen(mc, 0)
        true -> MailClient.new_search(query)
      end

    {
      :noreply,
      socket
      |> push_event("set_value", %{key: "recoverQuery", value: query})
      |> assign(
        info: info_mc(mc),
        mail_opened: false,
        page_title: query,
        list_mails: MailClient.mails_of(mc),
        list_tree: MailClient.tree_of(mc),
        mail_client: mc,
        last_query: query,
        buttons: [
          {:patch, "\u{1F527}", Routes.mail_path(Endpoint, :config), false},
          {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
          {:patch, "\u{1F4DD}", Routes.mail_path(Endpoint, :write, "#"), false},
          {:patch, "\u{1F4A4}", Routes.mail_path(Endpoint, :login), false}
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
              case MailClient.seen(nil, docid) do
                nil -> {nil, nil}
                mc -> {mc, nil}
              end

            _ ->
              mc = MailClient.new_search(query)

              case MailClient.mail_meta(mc, docid) do
                nil ->
                  case MailClient.seen(nil, docid) do
                    nil -> {nil, nil}
                    mc -> {mc, nil}
                  end

                _ ->
                  {MailClient.seen(mc, docid), query}
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
                page_title: "Mail not found",
                buttons: [
                  {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
                  {:patch, "\u{1f5C2}", Routes.mail_path(Endpoint, :find, @default_query), false},
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
                info: info_mc(mc),
                page_title: meta.subject,
                mail_client: mc,
                last_query: query,
                buttons: [
                  {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
                  {:patch, "\u{1F5C2}", Routes.mail_path(Endpoint, :find, query), false},
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
            page_title: "Mail not found",
            buttons: [
              {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
              {:patch, "\u{1F5C2}", Routes.mail_path(Endpoint, :find, @default_query), false},
              {:button, "\u{25C0}", "backward_message", true},
              {:button, "\u{25B6}", "forward_message", true}
            ]
          )
        }
    end
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
        mc = MailClient.seen(mc, docid)

        case MailClient.mail_meta(mc, docid) do
          nil ->
            {
              :noreply,
              socket
              |> put_flash(:error, "Mail not found")
              |> assign(
                info: info_mc(mc),
                page_title: "Mail not found",
                buttons: [
                  {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
                  {:patch, "\u{1F5C2}", Routes.mail_path(Endpoint, :find, query), false},
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
                info: info_mc(mc),
                page_title: meta.subject,
                mail_client: mc,
                buttons: [
                  {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
                  {:patch, "\u{1F5C2}", Routes.mail_path(Endpoint, :find, query), false},
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
            info: info_mc(mc),
            page_title: "Mail not found",
            buttons: [
              {:patch, "\u{1F50D}", Routes.mail_path(Endpoint, :search), false},
              {:patch, "\u{1F5C2}", Routes.mail_path(Endpoint, :find, query), false},
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
            live_action: :search,
            last_query: query,
            mail_opened: opened,
            mail_client: mc
          }
        } = socket
      ) do
    default_query =
      case opened do
        true -> MailClient.solo_query(mc)
        false -> query
      end

    MailClient.snooze()

    {
      :noreply,
      socket
      |> assign(
        default_query: default_query,
        page_title: "Search",
        info: "Search",
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
        archive_maildir: Configer.default(:archive_maildir),
        orbit_api_key: Configer.default(:orbit_api_key),
        orbit_workspace: Configer.default(:orbit_workspace),
        buttons: [
          {:button, "\u{1F4BE}", "config_save", false},
          {:button, "\u{2716}", "close_dialog", false}
        ]
      )
    }
  end

  def handle_params(_params, _url, %Socket{assigns: %{live_action: :draft}} = socket) do
    {subject, _recipients, text} = AddressVault.get_draft()

    {
      :noreply,
      socket
      |> assign(
        page_title: "Draft",
        info: subject,
        write_text: text || "",
        buttons: [
          {:patch, "\u{1F4DD}", Routes.mail_path(Endpoint, :write, "#"), false},
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
    {draft_subject, draft_recipients, draft_text} = AddressVault.get_draft()

    {
      :noreply,
      socket
      |> assign(
        page_title: "Write",
        info: "",
        recipients: recipients || draft_recipients || MailClient.default_recipients(),
        subject: subject || draft_subject || "",
        write_text: MailClient.quoted_text(nil, text) || draft_text || "",
        write_attachments: [],
        incoming_attachments: [],
        current_attachment: nil,
        write_chunk_outstanding: false,
        buttons: [
          {:button, "\u{1F4EC}", "send", false},
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
    {
      :noreply,
      socket
      |> assign(
        page_title: "Write",
        info: "",
        recipients: MailClient.default_recipients(mc, to),
        subject: MailClient.reply_subject(mc),
        write_text: MailClient.quoted_text(mc, text),
        write_attachments: [],
        incoming_attachments: [],
        current_attachment: nil,
        write_chunk_outstanding: false,
        buttons: [
          {:button, "\u{1F4EC}", "send", false},
          {:attach, "\u{1F4CE}", "write_attach", false},
          {:button, "\u{1F5D1}", "drop_attachments", false},
          {:patch, "\u{1F4C3}", Routes.mail_path(Endpoint, :draft), false},
          {:button, "\u{2716}", "close_write", false}
        ]
      )
    }
  end

  def handle_params(
        _params,
        _url,
        %Socket{
          assigns: %{
            live_action: :welcome,
            recover_query: query
          }
        } = socket
      ) do
    {:noreply, push_patch(socket, to: Routes.mail_path(Endpoint, :find, query))}
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
        %{"login" => %{"password" => ""}},
        %Socket{assigns: %{password_hash: nil, saved_password: ""}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event(
        "pw_submit",
        %{"login" => %{"password" => password}},
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
        %{"login" => %{"password" => password}},
        %Socket{assigns: %{recover_query: query, password_hash: nil, saved_password: password}} =
          socket
      ) do
    hash = Argon2.hash_pwd_salt(password)
    SelfConfiger.set_env(Configer, :password_hash, hash)

    {
      :noreply,
      socket
      |> clear_flash()
      |> assign(password_hash: hash)
      |> push_patch(to: Routes.mail_path(Endpoint, :find, query))
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
        %{"login" => %{"password" => password}},
        %Socket{assigns: %{recover_query: query, password_hash: hash}} = socket
      ) do
    case Argon2.verify_pass(password, hash) do
      true ->
        {:ok, token, _claims} = Guardian.build_token(System.get_env("USER"))

        {
          :noreply,
          socket
          |> clear_flash()
          |> push_event("set_value", %{key: "token", value: token})
          |> assign(auth: :logged_in)
          |> push_patch(to: Routes.mail_path(Endpoint, :find, query))
        }

      false ->
        {:noreply, put_flash(socket, :error, "Login failed")}
    end
  end

  def handle_event("search", %{"search" => %{"query" => ""}}, socket) do
    {:noreply, put_flash(socket, :error, "Query cannot be empty")}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
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
        "write_change",
        %{"_target" => [target | _], "mail" => %{"subject" => subject, "text" => text}} = mail,
        %Socket{assigns: %{recipients: recipients}} = socket
      ) do
    completion_list =
      cond do
        !String.starts_with?(target, "addr_") -> []
        String.length(mail[target]) < 2 -> []
        true -> AddressVault.start_with(mail[target])
      end

    recipients =
      0..(length(recipients) - 1)
      |> Enum.map(fn i ->
        MailClient.parse_recipient(mail["type_#{i}"], mail["addr_#{i}"])
      end)
      |> MailClient.normalize_recipients()

    AddressVault.put_draft(subject, recipients, text)

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
        %{"mail" => %{"subject" => subject, "text" => text}} = mail,
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
      |> MailClient.normalize_recipients()

    AddressVault.put_draft(subject, recipients, text)

    {
      :noreply,
      assign(socket,
        recipients: recipients,
        subject: subject,
        write_text: text
      )
    }
  end

  def handle_event(
        "send",
        _params,
        %Socket{
          assigns: %{
            auth: :logged_in,
            write_attachments: atts,
            current_attachment: nil,
            incoming_attachments: [],
            subject: subject,
            recipients: recipients,
            write_text: text,
            mail_client: mc
          }
        } = socket
      ) do
    # last one is always empty
    recipients = Enum.drop(recipients, -1)

    case MailClient.send_mail(mc, subject, recipients, text, Enum.reverse(atts)) do
      {:error, msg} ->
        {:noreply, put_flash(socket, :error, "Mail not sent: #{msg}")}

      {:ok, _} ->
        AddressVault.clear_draft()

        {
          :noreply,
          socket
          |> put_flash(:info, "Mail sent.")
          |> assign(
            recipients: [],
            write_text: "",
            subject: "",
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
    {
      :noreply,
      socket
      |> assign(
        recipients: [],
        write_text: "",
        subject: "",
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
          "config" => %{
            "my_name" => name,
            "my_addr" => addr,
            "my_addrs" => addrs,
            "my_lists" => lists,
            "archive_days" => days,
            "archive_maildir" => maildir,
            "orbit_api_key" => api_key,
            "orbit_workspace" => workspace
          }
        },
        socket
      ) do
    my_addr =
      case name do
        "" -> [nil | addr]
        _ -> [name | addr]
      end

    my_addrs = String.split(String.trim(addrs), "\n")
    my_lists = String.split(String.trim(lists), "\n")
    archive_maildir = String.trim(maildir)
    orbit_api_key = String.trim(api_key)
    orbit_workspace = String.trim(workspace)

    archive_days =
      case Integer.parse(days) do
        {n, ""} when n > 0 -> n
        _ -> Configer.default(:archive_days)
      end

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
        orbit_api_key: orbit_api_key,
        orbit_workspace: orbit_workspace
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
            orbit_workspace: orbit_workspace
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

    {
      :noreply,
      socket
      |> put_flash(:info, "Config saved")
      |> push_patch(to: close_action(socket))
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
        {:noreply, push_patch(socket, to: Routes.mail_path(Endpoint, :view, prev))}
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
        {:noreply, push_patch(socket, to: Routes.mail_path(Endpoint, :view, next))}
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
          {:text, ""} -> {:noreply, assign(socket, mail_content: {:html, body})}
          _ -> {:noreply, socket}
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

  defp info_mc(nil), do: "0/0"

  defp info_mc(mc) do
    "#{MailClient.unread_count(mc)} unread/#{MailClient.mail_count(mc)}"
  end

  defp open_mail(%Socket{assigns: %{mail_meta: meta}} = socket, meta) do
    assign(socket, mail_opened: true)
  end

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
end
