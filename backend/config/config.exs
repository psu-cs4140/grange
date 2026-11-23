import Config

config :grange, ecto_repos: [Grange.Repo]

# Crops ripen on a timer in dev/prod; tests drive `FarmStore.tick/1` directly.
config :grange, start_ticker: true

# The global day/night clock broadcasts a snapshot every second in dev/prod.
config :grange, start_world_clock: true

# Automatic administrator creation is opt-in and disabled by default. Even when
# enabled it never runs in production. Credentials must come from the
# environment; there is no built-in default login.
config :grange, start_admin: false
config :grange, env: config_env()

config :grange,
  admin_username: nil,
  admin_email: nil,
  admin_password: nil

config :grange, GrangeWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [json: GrangeWeb.ErrorJSON], layout: false],
  pubsub_server: Grange.PubSub,
  secret_key_base: "dev-secret-key-base-that-is-at-least-64-bytes-long-for-phoenix-ok"

# The /api/reset test hook is only routed when this is true. It is compiled
# into the router, so it stays off in production.
config :grange, enable_test_routes: false

config :phoenix, :json_library, Jason

# Transactional email goes through this adapter seam. The console adapter is
# the safe default; production overrides it with Mailtrap in runtime.exs.
config :grange, :mailer, Grange.Mailer.Console
config :grange, :app_url, "http://localhost:3200"

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
