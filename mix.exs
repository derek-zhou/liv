defmodule Liv.MixProject do
  use Mix.Project

  def project do
    [
      app: :liv,
      version: "0.7.0",
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers() ++ [:phoenix, :surface],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Liv.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:self_configer, "~> 0.1.1"},
      {:maildir_commander, "~> 0.6.5"},
      {:pop3client, "~> 1.3.1"},
      {:bbmustache, "~> 1.12"},
      {:memento, "~> 0.3.2"},
      {:html_sanitize_ex, "~> 1.4"},
      {:swoosh, "~> 1.5"},
      {:gen_smtp, "~> 1.1"},
      {:httpoison, "~> 1.7"},
      {:mime, "~> 1.6"},
      {:hackney, "~> 1.9"},
      {:argon2_elixir, "~> 2.4"},
      {:md, "~> 0.9.1"},
      {:string_naming, "~> 0.7.3"},
      {:surface, "~> 0.9.1"},
      {:phoenix, "~> 1.6.6"},
      {:phoenix_live_view, "~> 0.18.0"},
      {:phoenix_html, "~> 3.2"},
      {:phoenix_live_reload, "~> 1.3.3", only: :dev},
      {:phoenix_live_dashboard, "~> 0.7.0"},
      {:telemetry_metrics, "~> 0.6.1"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "cmd npm install --prefix assets"]
    ]
  end
end
