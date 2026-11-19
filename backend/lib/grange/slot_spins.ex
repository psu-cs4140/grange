defmodule Grange.SlotSpins do
  @moduledoc "Settles slot wagers and stores their results for safe retries."

  import Ecto.Query
  alias Grange.{CasinoRandom, Repo, User}

  @bets [1, 5, 10, 15, 20, 50]
  @multipliers %{"cherry" => 3, "bell" => 12, "diamond" => 50, "seven" => 200}

  def spin(user_id, spin_id, bet) when bet in @bets and is_binary(spin_id) do
    settle_round(user_id, spin_id, bet, %{"game" => "slots"}, fn ->
      reels = for _ <- 1..3, do: reel()
      %{"reels" => reels, "payout" => payout(reels, bet)}
    end)
  end

  def spin(_user_id, _spin_id, _bet), do: {:error, :invalid_spin}

  @doc "Settles a validated single-action casino round once."
  def settle_round(user_id, spin_id, stake, request, draw) do
    case Ecto.UUID.cast(spin_id) do
      {:ok, id} -> Repo.transaction(fn -> settle(user_id, id, stake, request, draw) end)
      :error -> {:error, :invalid_spin}
    end
  end

  defp settle(user_id, id, bet, request, draw) do
    # Claim the request before reading the wallet, acquiring SQLite's write lock.
    {count, _} =
      Repo.insert_all("slot_spins", [%{user_id: user_id, spin_id: id, bet: bet}],
        on_conflict: :nothing,
        conflict_target: [:user_id, :spin_id]
      )

    spin = from(s in "slot_spins", where: s.user_id == ^user_id and s.spin_id == ^id)
    user = Repo.get!(User, user_id)

    if count == 1 do
      if user.balance < bet, do: Repo.rollback(:insufficient_funds)
      result = draw.()
      balance = user.balance - bet + Map.fetch!(result, "payout")
      Repo.update!(Ecto.Changeset.change(user, balance: balance))
      record = Map.put(result, "request", request)
      Repo.update_all(from(s in spin, update: [set: [result: type(^record, :map)]]), [])
      Map.put(result, "balance", balance)
    else
      %{bet: original_bet, result: result} =
        Repo.one!(select(spin, [s], %{bet: s.bet, result: type(s.result, :map)}))

      original_request = Map.get(result, "request", %{"game" => "slots"})
      if original_bet != bet or original_request != request, do: Repo.rollback(:spin_conflict)
      result |> Map.delete("request") |> Map.put("balance", user.balance)
    end
  end

  defp payout([face, face, face], bet), do: Map.fetch!(@multipliers, face) * bet
  defp payout(_reels, _bet), do: 0

  defp reel do
    case CasinoRandom.draw(100) do
      roll when roll <= 50 -> "cherry"
      roll when roll <= 80 -> "bell"
      roll when roll <= 96 -> "diamond"
      _roll -> "seven"
    end
  end
end
