# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

# Configures the endpoint
config :liv, LivWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "4D1+yC63Qxp6AP6f8I54SGPhzvCCe0W0RCQCxsflI20MvGIgP7+KSEKJZp8u1W52",
  render_errors: [view: LivWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Liv.PubSub,
  live_view: [signing_salt: "D/E1V/7c"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
