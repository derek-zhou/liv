defmodule LivWeb.MailLive do
  use Surface.LiveView
  require Logger

  alias LivWeb.{Main, Find, Search, View, Login, Guardian}
  alias Phoenix.LiveView.Socket
  alias LivWeb.Router.Helpers, as: Routes
  alias Argon2
  alias :self_configer, as: SelfConfiger
  alias Liv.Configer
  alias Liv.MailClient

  # client side state
  data auth, :atom, default: nil
  data tz_offset, :integer, default: 0

  # the mail client app state
  data mail_client, :map, default: nil
  
  # for login
  # nil, logged_in, logged_out
  data saved_path, :string, default: ""
  data password_hash, :string,
    default: Application.get_env(:liv, :password_hash)
  data saved_password, :string, default: ""
  data password_prompt, :string, default: "Enter your password: "
  
  # for the header
  data title, :string, default: ""
  data info, :string, default: "Loading..."
  data buttons, :list, default: []

  # for the viewer
  data mail_meta, :map
  data mail_html, :string

  # to refer back
  data last_query, :string, default: ""
  data last_docid, :integer, default: 0
  
  # for the initial mount before login
  def handle_params(_params, _url,
    %Socket{assigns: %{live_action: :login}} = socket) do
    {
      :noreply,
      socket
      |> clear_flash()
      |> push_event("set_value", %{key: "token", value: ""})
      |> assign(auth: :logged_out, title: "Login as",
      password_hash: Application.get_env(:liv, :password_hash),
      password_prompt: "Enter your password: ",
      info: System.get_env("USER"),
      buttons: [])
    }
  end

  def handle_params(_params, url,
    %Socket{assigns: %{auth: nil}} = socket) do
    %URI{path: path} = URI.parse(url)
    {:noreply, assign(socket, saved_path: path)}
  end

  def handle_params(_params, _url,
    %Socket{assigns: %{auth: :logged_out}}) do
    exit("Unauthorized")
  end

  def handle_params(_params, _url,
    %Socket{assigns: %{live_action: :set_password}} = socket) do
    {
      :noreply,
      socket
      |> clear_flash()
      |> assign(title: "Set password of",
      info: System.get_env("USER"),
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
      |> clear_flash()
      |> assign(title: "LivBox",
      info: info_mc(mc),
      mail_client: mc,
      last_query: query,
      buttons: [
	{"\u{1f50d}", Routes.mail_path(socket, :search), false},
	{"\u{1f6aa}", Routes.mail_path(socket, :login), false}
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
	    next = MailClient.next(mc, docid) || 0
	    prev = MailClient.previous(mc, docid) || 0
	    html = MailClient.html_content(mc, docid)
	    {
	      :noreply,
	      socket
	      |> clear_flash()
	      |> assign(title: "LivMail",
		info: info_mc(mc),
		mail_client: mc,
		last_docid: docid,
		last_query: "msgid:#{meta.msgid}",
		mail_meta: meta,
		mail_html: html,
		buttons: [
		  {"\u{1f50d}", Routes.mail_path(socket, :search), false},
		  {"\u25c0", Routes.mail_path(socket, :view, prev), prev == 0},
		  {"\u25b6", Routes.mail_path(socket, :view, next), next == 0},
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
      info: "",
      mail_client: nil,
      buttons: [])
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
    {
      :noreply,
      socket
      |> assign(last_query: query)
    }
  end
  
  # no password hash 
  defp patch_action(%Socket{assigns: %{auth: :logged_out,
				       password_hash: nil}} = socket) do
    # temporarily log user in to set the password
    socket
    |> assign(auth: :logged_in)
    |> push_patch(to: Routes.mail_path(socket, :set_password))
  end

  defp patch_action(%Socket{assigns: %{auth: :logged_out}} = socket) do
    push_patch(socket, to: Routes.mail_path(socket, :login))
  end

  # no saved url
  defp patch_action(%Socket{assigns: %{saved_path: ""}} = socket) do
    push_patch(socket, to: Routes.mail_path(socket, :find, URI.encode("maildir:/")))
  end
  
  defp patch_action(%Socket{assigns: %{saved_path: path}} = socket) do
    socket
    |> assign(saved_path: "")
    |> push_patch(to: path)
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

  defp info_mc(mc) do
    "#{MailClient.unread_count(mc)}/#{MailClient.mail_count(mc)}"
  end

end
