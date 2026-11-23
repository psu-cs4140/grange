defmodule Grange.Application do
  @moduledoc false

  use Application

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
        clock_children() ++
        mailer_children() ++
        [GrangeWeb.Endpoint]

    opts = [strategy: :one_for_one, name: Grange.Supervisor]

    # `Grange.Migrator` has already applied the migrations by the time the
    # supervisor returns, so the Repo is ready for the admin bootstrap. The
    # bootstrap is opt-in, development-only, and never falls back to default
    # credentials; a missing credential logs a warning instead of failing boot.
    with {:ok, supervisor} <- Supervisor.start_link(children, opts) do
      Grange.AdminBootstrap.ensure()
      {:ok, supervisor}
    end
  end

  # The ticker is unnecessary in tests, which drive `FarmStore.tick/1` directly.
  defp ticker_children do
    if Application.get_env(:grange, :start_ticker, true), do: [Grange.FarmTicker], else: []
  end

  # The clock always runs so snapshots are available; only its broadcasts are
  # disabled in tests (see `start_world_clock` in config/test.exs).
  defp clock_children do
    [Grange.WorldClock, Grange.FarmPresence, Grange.SleepVotes]
  end

  # The console mailer captures messages in an Agent so the dev mailbox
  # endpoint (and e2e tests) can read verification/reset links back out. It is
  # only started when it is the configured adapter.
  defp mailer_children do
    if Grange.Mailer.impl() == Grange.Mailer.Console, do: [Grange.Mailer.Console], else: []
  end
end
