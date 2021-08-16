import Config

if config_env() == :prod do
  # In this file, we load production configuration and secrets
  # from environment variables. You can also hardcode secrets,
  # although such is generally not recommended and you have to
  # remember to add this file to your .gitignore.

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
    url: [host: "mail.3qin.us", scheme: "https", port: 443, path: "/#{System.get_env("USER")}"],
    cache_static_manifest: "priv/static/cache_manifest.json",
    http: [
      ip: {127, 0, 0, 1},
      port: String.to_integer(System.get_env("PORT") || "4001")
    ],
    secret_key_base: secret_key_base,
    server: true

  # for guardian
  config :liv, LivWeb.Guardian, secret_key: guardian_key
end
