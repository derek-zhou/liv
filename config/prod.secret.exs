# In this file, we load production configuration and secrets
# from environment variables. You can also hardcode secrets,
# although such is generally not recommended and you have to
# remember to add this file to your .gitignore.
use Mix.Config

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

guardian_key =
  System.get_env("GUARDIAN_KEY") ||
    raise """
    environment variable GUARDIAN_KEY is missing.
    You can generate one by calling: mix guardian.gen.secret
    """

config :liv, LivWeb.Endpoint,
  http: [
    ip: {127, 0, 0, 1},
    port: String.to_integer(System.get_env("PORT") || "4001")
  ],
  secret_key_base: secret_key_base

# for guardian
config :liv, LivWeb.Guardian, secret_key: guardian_key

# ## Using releases (Elixir v1.9+)
#
# If you are doing OTP releases, you need to instruct Phoenix
# to start each relevant endpoint:
#
config :liv, LivWeb.Endpoint, server: true
#
# Then you can assemble a release by calling `mix release`.
# See `mix help release` for more information.
