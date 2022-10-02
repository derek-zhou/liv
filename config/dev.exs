import Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :liv, LivWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    npm: [
      "run",
      "watch",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

# Watch static and templates for browser reloading.
config :liv, LivWeb.Endpoint,
  reloadable_compilers: [:phoenix, :elixir, :surface],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/gara_web/(live|views)/.*(ex)$",
      ~r"lib/gara_web/templates/.*(eex)$",
      ~r"lib/gara_web/(live|components)/.*(ex|js|sface)$"
    ]
  ]

# mailer
config :liv, Liv.Mailer, adapter: Swoosh.Adapters.Local

# Do not include metadata nor timestamps in development logs
config :logger,
       :console,
       format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
