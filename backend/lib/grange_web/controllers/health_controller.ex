defmodule GrangeWeb.HealthController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Grange.Accounts
  alias Grange.FarmStore

  def state(conn, _params) do
    json(conn, %{
      playerCount: length(Accounts.list_users()),
      farmCount: length(FarmStore.summaries())
    })
  end

  def reset(conn, _params) do
    Accounts.reset()
    # A dev reset must not remove the always-available default admin.
    Accounts.ensure_admin()
    FarmStore.reset()
    json(conn, %{ok: true})
  end
end
