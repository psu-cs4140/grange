defmodule Grange.Blackjack do
  @moduledoc "Server-owned blackjack deals, player actions, and settlement."

  alias Grange.CasinoDeck

  def apply_action(state, balance, %{"move" => "deal", "bet" => bet})
      when is_integer(bet) and bet >= 5 and bet <= 1_000_000_000 do
    cond do
      state["phase"] == "playerTurn" -> {:error, :invalid_action}
      balance < bet -> {:error, :insufficient_funds}
      true -> deal(bet, balance)
    end
  end

  def apply_action(%{"phase" => "playerTurn"} = state, balance, %{"move" => move}) do
    hand = Enum.at(state["hands"], state["activeHand"])
    opening = length(hand["cards"]) == 2
    single = length(state["hands"]) == 1

    case move do
      "hit" ->
        draw_for_hand(state, hand, balance, false)

      "stand" ->
        replace_and_advance(state, hand, balance)

      "double" when opening ->
        if balance >= hand["wager"] do
          draw_for_hand(
            state,
            %{hand | "wager" => hand["wager"] * 2},
            balance - hand["wager"],
            true
          )
        else
          {:error, :insufficient_funds}
        end

      "split" when opening ->
        split(state, hand, balance)

      "surrender" when opening and single ->
        replace_and_advance(state, %{hand | "result" => "surrender"}, balance)

      _ ->
        {:error, :invalid_action}
    end
  end

  def apply_action(_state, _balance, _request), do: {:error, :invalid_action}

  def public_state(state, balance) do
    hidden = state["phase"] == "playerTurn"
    dealer = state["dealer"] || []
    visible = if hidden, do: Enum.take(dealer, 1), else: dealer
    {dealer_total, dealer_soft} = value(visible)
    hands = state["hands"] || []
    active = state["activeHand"] || 0
    hand = Enum.at(hands, active)
    opening = hidden and length(hand["cards"]) == 2
    affordable = opening and hand["wager"] <= balance

    %{
      "phase" => state["phase"] || "betting",
      "bet" => state["bet"] || 5,
      "dealer" => visible,
      "dealerHidden" => hidden,
      "dealerTotal" => dealer_total,
      "dealerSoft" => dealer_soft,
      "hands" => Enum.with_index(hands, &visible_hand/2),
      "activeHand" => active,
      "message" => message(state["phase"]),
      "net" => state["net"] || 0,
      "betError" => nil,
      "canHit" => hidden,
      "canStand" => hidden,
      "canDouble" => affordable,
      "canSplit" => affordable and length(hands) < 4 and splittable?(hand["cards"]),
      "canSurrender" => opening and length(hands) == 1
    }
  end

  defp deal(bet, balance) do
    [a, b, c, d | deck] = CasinoDeck.shuffled()

    state = %{
      "phase" => "playerTurn",
      "bet" => bet,
      "activeHand" => 0,
      "deck" => deck,
      "dealer" => [a, b],
      "hands" => [hand([c, d], bet, false)]
    }

    if natural?([a, b]) or natural?([c, d]),
      do: settle(state, balance - bet),
      else: respond(state, balance - bet)
  end

  defp draw_for_hand(%{"deck" => [card | deck]} = state, hand, balance, forced) do
    hand = %{hand | "cards" => hand["cards"] ++ [card]}
    state = %{state | "deck" => deck}

    if forced or total(hand["cards"]) >= 21,
      do: replace_and_advance(state, hand, balance),
      else: state |> put_hand(hand) |> respond(balance)
  end

  defp split(%{"deck" => [a, b | deck]} = state, hand, balance) do
    cond do
      length(state["hands"]) >= 4 or not splittable?(hand["cards"]) ->
        {:error, :invalid_action}

      balance < hand["wager"] ->
        {:error, :insufficient_funds}

      true ->
        [first, second] = hand["cards"]
        aces = first["rank"] == "A" and second["rank"] == "A"
        left = %{hand([first, a], hand["wager"], true) | "done" => aces}
        right = %{hand([second, b], hand["wager"], true) | "done" => aces}
        index = state["activeHand"]
        hands = state["hands"] |> List.replace_at(index, left) |> List.insert_at(index + 1, right)
        state = %{state | "deck" => deck, "hands" => hands}
        balance = balance - hand["wager"]
        if aces, do: advance(state, balance), else: respond(state, balance)
    end
  end

  defp put_hand(state, hand),
    do: %{state | "hands" => List.replace_at(state["hands"], state["activeHand"], hand)}

  defp replace_and_advance(state, hand, balance),
    do: state |> put_hand(%{hand | "done" => true}) |> advance(balance)

  defp advance(state, balance) do
    case Enum.find_index(state["hands"], &(not &1["done"])) do
      nil -> state |> dealer_turn() |> settle(balance)
      index -> respond(%{state | "activeHand" => index}, balance)
    end
  end

  defp dealer_turn(%{"dealer" => dealer, "deck" => [card | deck]} = state) do
    {total, soft} = value(dealer)

    if total < 17 or (total == 17 and soft),
      do: dealer_turn(%{state | "dealer" => dealer ++ [card], "deck" => deck}),
      else: state
  end

  defp settle(state, balance) do
    dealer = state["dealer"]

    {hands, {returned, staked}} =
      Enum.map_reduce(state["hands"], {0, 0}, fn hand, {returned, staked} ->
        result = result(hand, dealer)
        wager = hand["wager"]
        {%{hand | "result" => result}, {returned + payout(result, wager), staked + wager}}
      end)

    state
    |> Map.merge(%{
      "phase" => "settled",
      "hands" => hands,
      "net" => returned - staked,
      "deck" => []
    })
    |> respond(balance + returned)
  end

  defp result(%{"result" => "surrender"}, _dealer), do: "surrender"

  defp result(hand, dealer) do
    player = total(hand["cards"])
    house = total(dealer)
    player_natural = not hand["split"] and natural?(hand["cards"])
    house_natural = natural?(dealer)

    cond do
      player > 21 -> "bust"
      player_natural and house_natural -> "push"
      player_natural -> "blackjack"
      house_natural -> "lose"
      house > 21 or player > house -> "win"
      player == house -> "push"
      true -> "lose"
    end
  end

  defp payout("blackjack", bet), do: div(bet * 5, 2)
  defp payout("win", bet), do: 2 * bet
  defp payout("push", bet), do: bet
  defp payout("surrender", bet), do: div(bet, 2)
  defp payout(_, _), do: 0

  defp respond(state, balance), do: {:ok, state, public_state(state, balance), balance}
  defp message("playerTurn"), do: "Hit or stand?"
  defp message("settled"), do: "Round over."
  defp message(_), do: "Choose a bet and deal."

  defp hand(cards, wager, split),
    do: %{"cards" => cards, "wager" => wager, "split" => split, "done" => false, "result" => nil}

  defp visible_hand(hand, index) do
    {total, soft} = value(hand["cards"])

    hand
    |> Map.take(~w(cards wager result))
    |> Map.merge(%{"id" => index, "total" => total, "soft" => soft})
  end

  defp natural?(cards), do: length(cards) == 2 and total(cards) == 21
  defp splittable?([a, b]), do: rank_value(a) == rank_value(b)
  defp total(cards), do: elem(value(cards), 0)

  defp value(cards) do
    sum = Enum.sum(Enum.map(cards, &rank_value/1))
    aces = Enum.count(cards, &(&1["rank"] == "A"))
    reduce_aces(sum, aces)
  end

  defp reduce_aces(total, aces) when total > 21 and aces > 0,
    do: reduce_aces(total - 10, aces - 1)

  defp reduce_aces(total, aces), do: {total, aces > 0}
  defp rank_value(%{"rank" => "A"}), do: 11
  defp rank_value(%{"rank" => rank}) when rank in ~w(J Q K), do: 10
  defp rank_value(%{"rank" => rank}), do: String.to_integer(rank)
end
