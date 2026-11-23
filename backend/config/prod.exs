import Config

config :grange, GrangeWeb.Endpoint, server: true
config :grange, enable_test_routes: false
# Production never creates an administrator on boot, even if an environment
# variable tries to enable the development bootstrap.
config :grange, start_admin: false

config :grange,
  admin_username: nil,
  admin_email: nil,
  admin_password: nil

config :logger, level: :info
