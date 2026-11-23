defmodule Grange.AdminBootstrap do
  @moduledoc """
  Optional administrator bootstrap for development.

  Automatic administrator creation runs only when `:env` is `:dev` and
  `:start_admin` is true. Credentials are read from the application
  environment (the `GRANGE_ADMIN_*` variables in dev). When a value is missing
  the bootstrap logs a warning and leaves the database untouched instead of
  falling back to a publicly known default login.
  """

  require Logger

  alias Grange.AdminAccounts

  @doc "Creates the configured admin when the bootstrap is enabled and safe."
  @spec ensure() :: :ok
  def ensure do
    if development?() and enabled?(), do: bootstrap(), else: :ok
  end

  @doc "True when the application opted into automatic admin creation."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:grange, :start_admin, false) == true

  defp development?, do: Application.get_env(:grange, :env) == :dev

  defp bootstrap do
    case AdminAccounts.ensure_admin() do
      {:ok, _admin} -> :ok
      {:error, reason} -> Logger.warning("admin bootstrap skipped: #{reason}")
    end
  end
end
