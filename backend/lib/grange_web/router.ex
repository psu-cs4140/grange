defmodule GrangeWeb.Router do
  @moduledoc false

  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
  end

  scope "/api", GrangeWeb do
    pipe_through(:api)

    post("/auth/register", AuthController, :register)
    post("/auth/login", AuthController, :login)
    post("/auth/logout", AuthController, :logout)
    get("/auth/me", AuthController, :me)

    get("/state", HealthController, :state)

    # Test hook: lets e2e runs start from a clean slate. Compiled out of
    # production builds.
    if Application.compile_env(:grange, :enable_test_routes, false) do
      post("/reset", HealthController, :reset)
    end
  end

  # SPA fallback: serve index.html for any unmatched client-side route.
  scope "/", GrangeWeb do
    get("/*path", PageController, :index)
  end
end
