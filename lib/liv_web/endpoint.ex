defmodule LivWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :liv

  socket "/live", Phoenix.LiveView.Socket, longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :liv,
    gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt web_modules _snowpack)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  if Mix.env() == :prod do
    plug Plug.RewriteOn, [:x_forwarded_proto, :x_forwarded_host, :x_forwarded_port]
  end

  plug LivWeb.Router
end
