defmodule LivWeb.MailLive do
  use Surface.LiveView
  require Logger

  alias LivWeb.{Main, Find, Search, View, Login, Guardian, Write, Config}
  alias Phoenix.LiveView.Socket
  alias LivWeb.Router.Helpers, as: Routes
  alias Argon2
  alias :self_configer, as: SelfConfiger
  alias :mc_configer, as: MCConfiger
  alias Liv.Configer
  alias Liv.MailClient
  alias Liv.AddressVault

  # client side state
  data auth, :atom, default: nil
  data tz_offset, :integer, default: 0

  # the mail client app state
  data mail_client, :map, default: nil
  
  # for login
  # nil, logged_in, logged_out
  data saved_path, :string, default: ""
  data password_hash, :string, default: ""
  data saved_password, :string, default: ""
  data password_prompt, :string, default: "Enter your password: "
  
  # for the header
  data title, :string, default: ""
  data info, :string, default: "Loading..."
  data buttons, :list, default: []

  # for the viewer
  data mail_meta, :map, default: nil
  data mail_html, :string, default: ""

  # to refer back in later 
  data last_query, :string, default: ""

  # for write
  data recipients, :list, default: []
  data addr_options, :list, default: []
  data subject, :string, default: ""
  data mail_text, :string, default: ""
  data preview_html, :string, default: ""

  # for config
  data my_addr, :list, default: [nil | "you@example.com"]
  data my_addrs, :list, default: []
  data my_lists, :list, default: []
  
  # for the initial mount before login
  def handle_params(_params, _url,
    %Socket{assigns: %{live_action: :login}} = socket) do
    user = System.get_env("USER")
    {
      :noreply,
      socket
      |> clear_flash()
      |> push_event("set_value", %{key: "token", value: ""})
      |> assign(auth: :logged_out, title: "Login as",
      page_title: "Login as #{user}",
      password_hash: Application.get_env(:liv, :password_hash),
      password_prompt: "Enter your password: ",
      info: user,
      buttons: [])
    }
  end

  def handle_params(_params, url,
    %Socket{assigns: %{auth: nil}} = socket) do
    %URI{path: path} = URI.parse(url)
    {:noreply,assign(socket, saved_path: path, page_title: "")}
  end

  def handle_params(_params, _url,
    %Socket{assigns: %{auth: :logged_out}}) do
    exit("Unauthorized")
  end

  def handle_params(_params, _url,
    %Socket{assigns: %{live_action: :set_password}} = socket) do
    user = System.get_env("USER")
    {
      :noreply,
      socket
      |> clear_flash()
      |> assign(title: "Set password of",
      info: user,
      page_title: "Set password of #{user}",
      password_hash: nil,
      saved_password: "",
      password_prompt: "Pick a password: ",
      buttons: [])
    }
  end

  def handle_params(%{"query" => query}, _url,
    %Socket{assigns: %{live_action: :find}} = socket) do
    query = URI.decode(query)
    mc = MailClient.new_search(query)
    {
      :noreply,
      socket
      |> assign(title: "LivBox",
      info: info_mc(mc),
      page_title: query,
      mail_client: mc,
      last_query: query,
      buttons: [
	{:patch, "\u{1f527}", Routes.mail_path(socket, :config), false},
	{:patch, "\u{1f50d}", Routes.mail_path(socket, :search), false},
	{:patch, "\u{2712}", Routes.mail_path(socket, :write, "#"), false},
	{:patch, "\u{1f4a4}", Routes.mail_path(socket, :login), false}
      ])
    }
  end

  def handle_params(%{"docid" => docid}, _url,
    %Socket{assigns: %{live_action: :view,
		       mail_client: mc}} = socket) do
    case Integer.parse(docid) do
      {docid, ""} ->
	mc = MailClient.seen(mc, docid)
	case MailClient.mail_meta(mc, docid) do
	  nil ->
	    {:noreply, put_flash(socket, :error, "Mail not found")}
	  meta ->
	    {
	      :noreply,
	      socket
	      |> assign(title: "LivMail",
		info: info_mc(mc),
		page_title: meta.subject,
		mail_client: mc,
		last_query: "msgid:#{meta.msgid}",
		mail_meta: meta,
		mail_html: MailClient.html_content(mc),
		buttons: [
		  {:patch, "\u{1f50d}", Routes.mail_path(socket, :search), false},
		  {:patch, "\u{2712}",
		   Routes.mail_path(socket, :write, tl(meta.from)),
		   false},
		  case MailClient.previous(mc, docid) do
		    nil -> {:patch, "\u25c0", "#", true}
		    prev -> {:patch, "\u25c0",
		    Routes.mail_path(socket, :view, prev), false}
		  end,
		  case MailClient.next(mc, docid) do
		    nil -> {:patch, "\u25b6", "#", true}
		    next -> {:patch, "\u25b6",
		    Routes.mail_path(socket, :view, next), false}
		  end
		])
	    }
	end
      _ ->
	{:noreply, put_flash(socket, :error, "Illegal docid")}
    end
  end

  def handle_params(_params, _url,
    %Socket{assigns: %{live_action: :search}} = socket) do
    {
      :noreply,
      socket
      |> assign(title: "LivSearch",
      page_title: "Search",
      info: "",
      mail_client: nil,
      buttons: [])
    }
  end

  def handle_params(_params, _url,
    %Socket{assigns: %{live_action: :config,
		       last_query: query }} = socket) do
    close_action = cond do
      query != "" -> Routes.mail_path(socket, :find, URI.encode(query))
      true -> default_action(socket)
    end
    {
      :noreply,
      socket
      |> assign(title: "LivConfig",
      page_title: "Config",
      info: "",
      my_addr: Configer.default(:my_address),
      my_addrs: Configer.default(:my_addresses),
      my_lists: Configer.default(:my_email_lists),
      buttons: [
	{:button, "\u{1F4BE}", "config_save", false},
	{:patch, "\u{2716}", close_action, false}
      ])
    }
  end

  def handle_params(%{"to" => to}, _url,
    %Socket{assigns: %{live_action: :write,
		       last_query: query,
		       mail_client: mc}} = socket) do
    close_action = cond do
      mc && mc.docid > 0 -> Routes.mail_path(socket, :view, mc.docid)
      query != "" -> Routes.mail_path(socket, :find, URI.encode(query))
      true -> default_action(socket)
    end

    {
      :noreply,
      socket
      |> assign(title: "LivWrite",
      page_title: "Write",
      info: "",
      recipients: MailClient.default_recipients(mc, to),
      subject: MailClient.reply_subject(mc),
      mail_text: MailClient.quoted_text(mc),
      buttons: [
	{:button, "\u{1F4EC}", "send", false},
	{:patch, "\u{2716}", close_action, false}
      ])
    }
  end

  def handle_params(_params, _url, socket) do
    {:noreply, patch_action(socket)}
  end
  
  def handle_event("get_value", values, socket) do
    {
      :noreply,
      socket
      |> fetch_token(values)
      |> fetch_tz_offset(values)
      |> fetch_locale(values)
      |> patch_action()
    }
  end

  def handle_event("pw_submit",
    %{"login" => %{"password" => ""}},
    %Socket{assigns: %{password_hash: nil,
		       saved_password: ""}} = socket) do
    {:noreply, socket}
  end

  def handle_event("pw_submit",
    %{"login" => %{"password" => password}},
    %Socket{assigns: %{password_hash: nil,
		       saved_password: ""}} = socket) do
    {
      :noreply,
      socket
      |> clear_flash()
      |> assign(saved_password: password,
      password_prompt: "Re-enter the password: ")
    }
  end
  
  def handle_event("pw_submit",
    %{"login" => %{"password" => password}},
    %Socket{assigns: %{password_hash: nil,
		       saved_password: password}} = socket) do
    hash = Argon2.hash_pwd_salt(password)
    SelfConfiger.set_env(Configer, :password_hash, hash)
    {
      :noreply,
      socket
      |> clear_flash()
      |> assign(password_hash: hash)
      |> patch_action()
    }
  end
  
  def handle_event("pw_submit", _,
    %Socket{assigns: %{password_hash: nil}} = socket) do
    {
      :noreply,
      socket
      |> put_flash(:error, "Passwords do not match")
      |> assign(saved_password: "",
      password_prompt: "Enter your password: ")
    }
  end
  
  def handle_event("pw_submit",
    %{"login" => %{"password" => password}},
    %Socket{assigns: %{password_hash: hash}} = socket) do
    case Argon2.verify_pass(password, hash) do
      true ->
	{:ok, token, _claims} =
	  Guardian.build_token(System.get_env("USER"))
	{
	  :noreply,
	  socket
	  |> clear_flash()
	  |> push_event("set_value", %{key: "token", value: token})
	  |> assign(auth: :logged_in)
	  |> patch_action()
	}
      false ->
	{:noreply, put_flash(socket, :error, "Login failed")}
    end
  end

  def handle_event("search",
    %{"search" => %{"query" => query}},
    socket) do
    Logger.notice("The query is #{query}.")
    {
      :noreply,
      socket
      |> push_patch(to: Routes.mail_path(socket, :find, URI.encode(query)))
    }
  end

  def handle_event("pick_search_example", %{"query" => query}, socket) do
    {:noreply, assign(socket, last_query: query)}
  end

  def handle_event("write_change",
    %{"_target" => [target | _],
      "mail" => %{"subject" => subject,
		  "text" => text}} = mail,
    %Socket{assigns: %{recipients: recipients}} = socket) do
    completion_list = cond do
      ! String.starts_with?(target, "addr_") -> []
      String.length(mail[target]) < 2 -> []
      true -> AddressVault.start_with(mail[target])
    end

    recipients =
    (0 .. length(recipients) - 1)
    |> Enum.map(fn i ->
      MailClient.parse_recipient(mail["type_#{i}"], mail["addr_#{i}"])
    end)
    |> MailClient.normalize_recipients()
    {
      :noreply,
      assign(socket, recipients: recipients, subject: subject,
	addr_options: completion_list, mail_text: text)
    }
  end

  def handle_event("send", _params,
    %Socket{assigns: %{subject: subject,
		       recipients: recipients,
		       last_query: query,
		       mail_text: text,
		       mail_client: mc}} = socket) do
    # last one is always empty
    recipients = Enum.drop(recipients, -1)
    case MailClient.send_mail(mc, subject, recipients, text) do
      {:error, msg} ->
	{:noreply, put_flash(socket, :error, "Mail not sent: #{msg}")}
      {:ok, _} ->
	close_action = cond do
	  mc && mc.docid > 0 -> Routes.mail_path(socket, :view, mc.docid)
	  query != "" -> Routes.mail_path(socket, :find, URI.encode(query))
	  true -> default_action(socket)
	end

	{
	  :noreply,
	  socket
	  |> put_flash(:info, "Mail sent.")
	  |> assign(recipients: [], mail_text: "", subject: "")
	  |> push_patch(to: close_action)
	}
    end
  end
  
  def handle_event("config_change",
    %{"config" => %{"my_name" => name,
		    "my_addr" => addr,
		    "my_addrs" => addrs,
		    "my_lists" => lists }}, socket) do
    my_addr = case name do
		"" -> [ nil | addr ]
		_ -> [name | addr ]
	      end
    my_addrs = String.split(String.trim(addrs), "\n")
    my_lists = String.split(String.trim(lists), "\n")

    socket = case my_addrs do
	       [^addr | _] -> clear_flash(socket)
	       _ ->
		 put_flash(socket, :error,
		   "Your list of address should has your primary address as the first one")
	     end
    {
      :noreply,
      assign(socket, my_addr: my_addr, my_addrs: my_addrs, my_lists: my_lists)
    }
  end

  def handle_event("config_save", _params,
    %Socket{assigns: %{last_query: query,
		       my_addr: my_addr,
		       my_addrs: my_addrs,
		       my_lists: my_lists}} = socket) do
    close_action = cond do
      query != "" -> Routes.mail_path(socket, :find, URI.encode(query))
      true -> default_action(socket)
    end

    Configer
    |> SelfConfiger.set_env(:my_address, my_addr)
    |> SelfConfiger.set_env(:my_addresses, my_addrs)
    |> SelfConfiger.set_env(:my_email_lists, my_lists)

    # MC need the same set of config for archiving
    SelfConfiger.set_env(MCConfiger, :my_addresses, my_addrs)

    {
      :noreply,
      socket
      |> put_flash(:info, "Config saved")
      |> push_patch(to: close_action)
    }
  end

  # not logged in
  defp patch_action(%Socket{assigns: %{auth: :logged_out}} = socket) do
    case Application.get_env(:liv, :password_hash) do
      nil ->
	# temporarily log user in to set the password
	socket
	|> assign(auth: :logged_in)
	|> push_patch(to: Routes.mail_path(socket, :set_password))
      hash ->
	socket
	|> assign(password_hash: hash)
	|> push_patch(to: Routes.mail_path(socket, :login))
    end
  end

  # no saved url
  defp patch_action(%Socket{assigns: %{saved_path: ""}} = socket) do
    push_patch(socket, to: default_action(socket))
  end
  
  defp patch_action(%Socket{assigns: %{saved_path: path}} = socket) do
    socket
    |> assign(saved_path: "")
    |> push_patch(to: path)
  end

  defp default_action(socket) do
    Routes.mail_path(socket, :find, URI.encode("maildir:/"))
  end

  defp fetch_token(socket, %{"token" => token}) do
    assign(socket, auth:
      case Guardian.decode_token(token) do
	nil -> :logged_out
	_ -> :logged_in
      end)
  end
  defp fetch_token(socket, _), do: assign(socket, auth: :logged_out)

  defp fetch_tz_offset(socket, %{"timezoneOffset" => offset}) do
    assign(socket, tz_offset: offset)
  end
  defp fetch_tz_offset(socket, _), do: socket

  defp fetch_locale(socket, %{"language" => locale}) do
    Gettext.put_locale(LivWeb.Gettext, locale)
    socket
  end

  defp fetch_locale(socket, _) do
    Gettext.put_locale(LivWeb.Gettext, "en")
    socket
  end

  defp info_mc(mc) do
    "#{MailClient.unread_count(mc)}/#{MailClient.mail_count(mc)}"
  end

end
