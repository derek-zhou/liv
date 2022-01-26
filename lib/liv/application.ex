defmodule Liv.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      LivWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Liv.PubSub},
      # configer to persist configuration
      {:self_configer, name: Liv.Configer},
      # draft server
      Liv.DraftServer,
      # the orbit gen server
      Liv.Orbit,
      # Start the Endpoint (http/https)
      LivWeb.Endpoint
      # Start a worker by calling: Liv.Worker.start_link(arg)
      # {Liv.Worker, arg}
    ]

    Application.put_env(:maildir_commander, :housekeeper, {Liv.MailClient, :archive_job, []})

    Application.put_env(
      :maildir_commander,
      :put_pasteboard,
      {Liv.AddressVault, :put_pasteboard, []}
    )

    Application.put_env(
      :maildir_commander,
      :get_pasteboard,
      {Liv.AddressVault, :get_pasteboard, []}
    )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Liv.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    LivWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
