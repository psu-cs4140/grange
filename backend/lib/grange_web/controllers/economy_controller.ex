defmodule GrangeWeb.EconomyController do
  @moduledoc """
  Persists Grangecoin balance changes for the signed-in account.

  Legacy client-driven debits and administrator-only development credits.
  """

  use Phoenix.Controller, formats: [:json]

  alias Grange.Accounts
  alias Grange.Blackjack
  alias Grange.CasinoHands
  alias Grange.Poker
  alias Grange.Roulette
  alias Grange.SlotSpins

  @session_key :user_token

  def blackjack(conn, _params), do: resume_hand(conn, "blackjack", Blackjack)
  def poker(conn, _params), do: resume_hand(conn, "poker", Poker)

  def blackjack_action(conn, params), do: hand_action(conn, params, "blackjack", Blackjack)
  def poker_action(conn, params), do: hand_action(conn, params, "poker", Poker)

  defp resume_hand(conn, game, rules) do
    case current_user(conn) do
      nil ->
        conn |> put_status(:unauthorized) |> json(%{error: "not signed in"})

      user ->
        result = CasinoHands.resume(user.id, game, &rules.public_state(&1, user.balance))
        json(conn, Map.put(result, "balance", user.balance))
    end
  end

  defp hand_action(conn, params, game, rules) do
    case current_user(conn) do
      nil ->
        conn |> put_status(:unauthorized) |> json(%{error: "not signed in"})

      user ->
        request = Map.take(params, ["move", "bet", "amount"])
        transition = &rules.apply_action(&1, &2, request)

        case CasinoHands.act(
               user.id,
               game,
               params["action_id"],
               params["version"],
               request,
               transition
             ) do
          {:ok, result} ->
            json(conn, result)

          {:error, error} when error in [:stale_hand, :action_conflict] ->
            conn |> put_status(:conflict) |> json(%{error: "The hand changed. Reload the table."})

          {:error, :insufficient_funds} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "Not enough Grangecoin."})

          {:error, :invalid_action} ->
            conn |> put_status(:bad_request) |> json(%{error: "Invalid table action."})
        end
    end
  end

  def spin_slots(conn, params) do
    settle_spin(conn, fn user_id -> SlotSpins.spin(user_id, params["spin_id"], params["bet"]) end)
  end

  def spin_roulette(conn, params) do
    settle_spin(conn, fn user_id -> Roulette.spin(user_id, params["spin_id"], params["bets"]) end)
  end

  defp settle_spin(conn, spin) do
    with %{id: user_id} <- current_user(conn),
         {:ok, result} <- spin.(user_id) do
      json(conn, result)
    else
      nil ->
        conn |> put_status(:unauthorized) |> json(%{error: "not signed in"})

      {:error, :insufficient_funds} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Not enough Grangecoin."})

      {:error, :spin_conflict} ->
        conn |> put_status(:conflict) |> json(%{error: "Spin ID already used for another bet."})

      {:error, :invalid_spin} ->
        conn |> put_status(:bad_request) |> json(%{error: "Invalid spin."})
    end
  end

  def transaction(conn, params) do
    case current_user(conn) do
      nil ->
        conn |> put_status(:unauthorized) |> json(%{ok: false, error: "not signed in"})

      user ->
        apply_delta(conn, user, params)
    end
  end

  defp apply_delta(conn, %{is_admin: false}, %{"delta" => delta})
       when is_integer(delta) and delta > 0 do
    conn
    |> put_status(:forbidden)
    |> json(%{ok: false, error: "wallet credit requires authorization"})
  end

  defp apply_delta(conn, user, params) do
    case Accounts.apply_balance_delta(user.id, Map.get(params, "delta")) do
      {:ok, balance} ->
        json(conn, %{ok: true, balance: balance})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{ok: false, error: reason})
    end
  end

  defp current_user(conn) do
    case Accounts.resolve_token(get_session(conn, @session_key)) do
      {:ok, user} -> user
      :error -> nil
    end
  end
end
