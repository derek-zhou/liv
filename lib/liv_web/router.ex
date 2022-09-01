defmodule LivWeb.Router do
  use LivWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_root_layout, {LivWeb.LayoutView, :root}
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LivWeb do
    pipe_through :browser

    live "/", MailLive, :welcome
    live "/login", MailLive, :login
    live "/set_password", MailLive, :set_password
    live "/find/:query", MailLive, :find
    live "/view/:docid", MailLive, :view
    live "/boomerang", MailLive, :boomerang
    live "/search", MailLive, :search
    live "/config", MailLive, :config
    live "/draft", MailLive, :draft
    live "/write/:to", MailLive, :write
    live "/address_book", MailLive, :address_book
  end

  if Mix.env() == :dev do
    # If using Phoenix
    forward "/sent_emails", Plug.Swoosh.MailboxPreview
  end

  # Other scopes may use custom stacks.
  # scope "/api", LivWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: LivWeb.Telemetry
    end
  end
end
