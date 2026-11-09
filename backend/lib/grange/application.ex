defmodule Grange.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    # The Migrator runs the boot migrations before the ticker and Endpoint start,
    # so the web server never serves a request against an unmigrated database.
    children =
      [
        {Phoenix.PubSub, name: Grange.PubSub},
        Grange.Repo,
        GrangeWeb.Presence,
        Grange.Migrator
      ] ++
        ticker_children() ++
        [GrangeWeb.Endpoint]

    opts = [strategy: :one_for_one, name: Grange.Supervisor]

    # `Grange.Migrator` has already applied the migrations by the time the
    # supervisor returns, so the Repo is ready for the admin bootstrap.
    with {:ok, supervisor} <- Supervisor.start_link(children, opts) do
      ensure_admin()
      {:ok, supervisor}
    end
  end

  # The ticker is unnecessary in tests, which drive `FarmStore.tick/1` directly.
  defp ticker_children do
    if Application.get_env(:grange, :start_ticker, true), do: [Grange.FarmTicker], else: []
  end

  # The default admin is baseline data, not something an operator should have
  # to remember to create before the game is usable.
  defp ensure_admin do
    case Grange.Accounts.ensure_admin() do
      {:ok, _admin} -> :ok
      {:error, reason} -> Logger.warning("could not ensure the default admin: #{reason}")
    end
  end
end
