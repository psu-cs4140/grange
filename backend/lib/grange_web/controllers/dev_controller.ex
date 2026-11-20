defmodule GrangeWeb.DevController do
  @moduledoc """
  Test-only shortcuts for the browser suite.

  Every action is mounted only while `enable_test_routes` is on (development
  and test), exactly like `/api/reset`, so a production build cannot reach it.
  """

  use Phoenix.Controller, formats: [:json]

  alias Grange.{Accounts, Barn, Crops, FarmStore, NpcQuest}

  @session_key :user_token

  @doc "Funds the signed-in fixture account during a browser test run."
  def fund_wallet(conn, %{"amount" => amount}) when is_integer(amount) and amount in 1..100_000 do
    if System.get_env("GRANGE_E2E") == "1" do
      case Accounts.resolve_token(get_session(conn, @session_key)) do
        {:ok, user} ->
          {:ok, balance} = Accounts.apply_balance_delta(user.id, amount)
          json(conn, %{ok: true, balance: balance})

        :error ->
          unauthorized(conn)
      end
    else
      GrangeWeb.FallbackController.not_found(conn, %{})
    end
  end

  def fund_wallet(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{ok: false, error: "invalid fixture amount"})
  end

  @doc """
  Seeds the signed-in player's farmhand quest and/or barn.

  Body: `{"stage": ..., "counters": {"tomatoes": 10}, "barn": {"tomato": 10}}`.
  Every field is optional; an omitted stage is derived from the counters.
  """
  def npc(conn, params) do
    case Accounts.resolve_token(get_session(conn, @session_key)) do
      {:ok, user} ->
        FarmStore.ensure(user.username)
        seed_npc(conn, user.username, params)

      :error ->
        unauthorized(conn)
    end
  end

  defp seed_npc(conn, owner, params) do
    with {:ok, _npc} <- NpcQuest.force(owner, params),
         :ok <- fill_barn(owner, Map.get(params, "barn")),
         {:ok, farm} <- FarmStore.refresh(owner) do
      npc = NpcQuest.status(owner)
      # The farm snapshot has no quest fields, so tell the room directly.
      GrangeWeb.Endpoint.broadcast("farm:" <> owner, "npcUpdate", %{npc: npc})
      json(conn, %{ok: true, npc: npc, barn: farm.barn})
    else
      {:error, reason} when is_binary(reason) ->
        conn |> put_status(:bad_request) |> json(%{ok: false, error: reason})
    end
  end

  defp fill_barn(_owner, nil), do: :ok

  defp fill_barn(owner, barn) when is_map(barn) do
    Enum.reduce_while(barn, :ok, fn {item, count}, :ok ->
      if is_binary(item) and is_integer(count) and count > 0 and Crops.get(item) do
        Barn.add(owner, item, count)
        {:cont, :ok}
      else
        {:halt, {:error, "invalid barn"}}
      end
    end)
  end

  defp fill_barn(_owner, _barn), do: {:error, "invalid barn"}

  defp unauthorized(conn) do
    conn |> put_status(:unauthorized) |> json(%{ok: false, error: "not signed in"})
  end
end
