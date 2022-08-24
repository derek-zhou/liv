defmodule Liv.Configer do
  @app :liv

  alias :self_configer, as: SelfConfiger

  @doc """
  load configuration into user data format
  """
  def default(:my_address), do: default_value(:my_address, [nil | "you@example.com"])
  def default(:my_addresses), do: default_value(:my_addresses, ["you@example.com"])
  def default(:my_email_lists), do: default_value(:my_email_lists, [])
  def default(:saved_addresses), do: default_value(:saved_addresses, [])
  def default(:archive_days), do: default_value(:archive_days, 30)
  def default(:archive_maildir), do: default_value(:archive_maildir, "/.Archive")
  def default(:orbit_api_key), do: default_value(:orbit_api_key, "")
  def default(:orbit_workspace), do: default_value(:orbit_workspace, "")
  def default(:token_ttl), do: default_value(:token_ttl, 30 * 24 * 3600)

  def default(:remote_mail_boxes) do
    :remote_mail_boxes
    |> default_value([])
    |> Enum.map(&Map.new(&1))
  end

  def default(:sending_method) do
    config = Application.get_env(@app, Liv.Mailer)
    data = %{username: "", password: "", hostname: "", api_key: ""}

    case config[:adapter] do
      Swoosh.Adapters.Sendgrid ->
        {:sendgrid, %{data | api_key: config[:api_key]}}

      Swoosh.Adapters.SMTP ->
        case config[:relay] do
          "localhost" ->
            {:local, data}

          hostname ->
            {:remote,
             %{
               data
               | hostname: hostname,
                 username: config[:username],
                 password: config[:password]
             }}
        end

      _ ->
        {:local, data}
    end
  end

  @doc """
  serialize user configration format into application format
  """
  def update_sending_method(mod, :local, _data) do
    SelfConfiger.set_env(mod, Liv.Mailer, adapter: Swoosh.Adapters.SMTP, relay: "localhost")
  end

  def update_sending_method(mod, :remote, %{
        username: username,
        password: password,
        hostname: hostname
      }) do
    SelfConfiger.set_env(mod, Liv.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: hostname,
      username: username,
      password: password,
      ssl: true,
      tls: :always,
      auth: :always,
      port: 587
    )
  end

  def update_sending_method(mod, :sendgrid, %{api_key: api_key}) do
    SelfConfiger.set_env(mod, Liv.Mailer,
      adapter: Swoosh.Adapters.Sendgrid,
      api_key: api_key
    )
  end

  @doc """
  update the remote mail boxes
  """
  def update_remote_mail_boxes(mod, boxes) do
    SelfConfiger.set_env(mod, :remote_mail_boxes, Enum.map(boxes, &Keyword.new(&1)))
  end

  defp default_value(key, default), do: Application.get_env(@app, key, default)
end
