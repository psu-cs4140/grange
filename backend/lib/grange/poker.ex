defmodule Grange.Poker do
  @moduledoc "Persistent heads-up Hold'em with server-owned cards and wagers."

  alias Grange.{CasinoDeck, CasinoRandom, PokerHand}

  @blind 10
  @dealer_stack 1000
  @strength {0.16, 0.36, 0.52, 0.66, 0.76, 0.86, 0.93, 0.98, 1.0}

  def apply_action(state, balance, %{"move" => "deal"}) do
    stack = state["dealerStack"] || @dealer_stack

    cond do
      state["phase"] == "playerTurn" -> {:error, :invalid_action}
      balance < @blind -> {:error, :insufficient_funds}
      true -> deal(if(stack < @blind, do: @dealer_stack, else: stack), balance)
    end
  end

  def apply_action(%{"phase" => "playerTurn"} = state, balance, request) do
    case request do
      %{"move" => "fold"} ->
        finish(state, balance, "dealer", 0, "You folded.")

      %{"move" => move} ->
        take_turn(state, balance, :player, move, request["amount"])

      _ ->
        {:error, :invalid_action}
    end
  end

  def apply_action(_, _, _), do: {:error, :invalid_action}

  defp deal(stack, balance) do
    [a, b, c, d | deck] = CasinoDeck.shuffled()

    state = %{
      "deck" => deck,
      "playerHole" => [a, b],
      "dealerHole" => [c, d],
      "community" => [],
      "phase" => "playerTurn",
      "street" => "preflop",
      "dealerStack" => stack - @blind,
      "playerCommitted" => 5,
      "dealerCommitted" => @blind,
      "playerTotal" => 5,
      "dealerTotal" => @blind,
      "currentBet" => @blind,
      "minRaise" => @blind,
      "acted" => false,
      "message" => "You posted $5. Call $5 to see a flop."
    }

    respond(state, balance - 5)
  end

  defp take_turn(state, balance, actor, move, amount) do
    mine = committed(state, actor)
    needed = state["currentBet"] - mine
    limit = max_raise(state, balance)

    case move do
      "check" when needed == 0 ->
        after_turn(state, balance, actor)

      "call" when needed > 0 ->
        if available(state, balance, actor) >= needed do
          {next, wallet} = commit(state, balance, actor, needed)
          after_turn(next, wallet, actor)
        else
          {:error, :insufficient_funds}
        end

      "raise" when is_integer(amount) ->
        target = min(amount, limit)
        increase = target - state["currentBet"]

        if increase > 0 and (increase >= state["minRaise"] or target == limit) do
          {next, wallet} = commit(state, balance, actor, target - mine)

          next = %{
            next
            | "currentBet" => target,
              "minRaise" => max(increase, state["minRaise"]),
              "acted" => false
          }

          pass(next, wallet, actor)
        else
          {:error, :invalid_action}
        end

      _ ->
        {:error, :invalid_action}
    end
  end

  defp after_turn(state, balance, actor) do
    if state["acted"] or balance == 0 or state["dealerStack"] == 0 do
      next_street(state, balance)
    else
      pass(%{state | "acted" => true}, balance, actor)
    end
  end

  defp pass(state, balance, :player), do: dealer_turn(state, balance)
  defp pass(state, balance, :dealer), do: respond(state, balance)

  defp next_street(state, balance) do
    cond do
      state["street"] == "river" or balance == 0 or state["dealerStack"] == 0 ->
        showdown(state, balance)

      true ->
        {street, count} =
          case state["street"] do
            "preflop" -> {"flop", 3}
            "flop" -> {"turn", 1}
            "turn" -> {"river", 1}
          end

        {cards, deck} = Enum.split(state["deck"], count)

        next = %{
          state
          | "street" => street,
            "deck" => deck,
            "community" => state["community"] ++ cards,
            "playerCommitted" => 0,
            "dealerCommitted" => 0,
            "currentBet" => 0,
            "minRaise" => @blind,
            "acted" => false
        }

        dealer_turn(next, balance)
    end
  end

  defp dealer_turn(state, balance) do
    needed = state["currentBet"] - state["dealerCommitted"]
    strength = strength(state)
    roll = CasinoRandom.draw(100) / 100
    pot = pot(state)
    odds = if needed > 0, do: needed / (pot + needed), else: 0

    fraction =
      cond do
        needed == 0 and strength > 0.8 -> 0.75
        needed == 0 and (strength > 0.62 or roll < 0.1) -> 0.5
        strength > 0.8 and roll < 0.55 -> 0.6
        strength > 0.55 and roll < 0.18 -> 0.5
        true -> nil
      end

    cond do
      fraction && max_raise(state, balance) > state["currentBet"] ->
        target = state["currentBet"] + max(state["minRaise"], trunc(pot * fraction))
        take_turn(state, balance, :dealer, "raise", target)

      needed == 0 ->
        take_turn(state, balance, :dealer, "check", nil)

      strength > 0.55 or (strength > odds + 0.12 and roll >= 0.3) or
        (strength > odds and roll < 0.5) or roll < 0.08 ->
        take_turn(state, balance, :dealer, "call", nil)

      true ->
        finish(state, balance, "player", pot, "The dealer folded.")
    end
  end

  defp strength(%{"community" => []} = state) do
    [a, b] = state["dealerHole"]
    [high, low] = Enum.sort([PokerHand.rank(a), PokerHand.rank(b)], :desc)

    if high == low do
      min(0.95, 0.5 + high / 30)
    else
      suited = if a["suit"] == b["suit"], do: 0.04, else: 0
      connected = if high - low == 1, do: 0.03, else: 0
      broadway = if high >= 13 and low >= 10, do: 0.08, else: 0
      min(0.95, (high + low) / 40 + suited + connected + broadway)
    end
  end

  defp strength(state) do
    {category, _} = PokerHand.best(state["dealerHole"] ++ state["community"])
    elem(@strength, category)
  end

  defp showdown(state, balance) do
    board = state["community"] ++ Enum.take(state["deck"], 5 - length(state["community"]))
    player = PokerHand.best(state["playerHole"] ++ board)
    dealer = PokerHand.best(state["dealerHole"] ++ board)

    state =
      Map.merge(state, %{
        "street" => "river",
        "community" => board,
        "playerBest" => PokerHand.category(player),
        "dealerBest" => PokerHand.category(dealer)
      })

    cond do
      player > dealer -> finish(state, balance, "player", pot(state), "You win.")
      player < dealer -> finish(state, balance, "dealer", 0, "The dealer wins.")
      true -> finish(state, balance, "split", div(pot(state), 2), "Split pot.")
    end
  end

  defp finish(state, balance, winner, payout, message) do
    state
    |> Map.merge(%{
      "phase" => "settled",
      "deck" => [],
      "winner" => winner,
      "net" => payout - state["playerTotal"],
      "message" => message
    })
    |> respond(balance + payout)
  end

  defp commit(state, balance, :player, amount),
    do:
      {%{
         state
         | "playerCommitted" => state["playerCommitted"] + amount,
           "playerTotal" => state["playerTotal"] + amount
       }, balance - amount}

  defp commit(state, balance, :dealer, amount),
    do:
      {%{
         state
         | "dealerCommitted" => state["dealerCommitted"] + amount,
           "dealerTotal" => state["dealerTotal"] + amount,
           "dealerStack" => state["dealerStack"] - amount
       }, balance}

  defp available(_state, balance, :player), do: balance
  defp available(state, _balance, :dealer), do: state["dealerStack"]
  defp committed(state, :player), do: state["playerCommitted"]
  defp committed(state, :dealer), do: state["dealerCommitted"]
  defp pot(state), do: (state["playerTotal"] || 0) + (state["dealerTotal"] || 0)

  defp max_raise(state, balance),
    do:
      min(
        (state["playerCommitted"] || 0) + balance,
        (state["dealerCommitted"] || 0) + (state["dealerStack"] || @dealer_stack)
      )

  defp respond(state, balance), do: {:ok, state, public_state(state, balance), balance}

  def public_state(state, balance) do
    phase = state["phase"] || "idle"
    active = phase == "playerTurn"
    current = state["currentBet"] || 0
    call = if active, do: current - state["playerCommitted"], else: 0
    limit = max_raise(state, balance)

    %{
      "phase" => phase,
      "street" => state["street"] || "preflop",
      "dealerStack" => state["dealerStack"] || @dealer_stack,
      "pot" => pot(state),
      "playerHole" => state["playerHole"] || [],
      "dealerHole" => visible_dealer(state, phase),
      "dealerHidden" => phase != "settled",
      "community" => state["community"] || [],
      "playerCommitted" => state["playerCommitted"] || 0,
      "dealerCommitted" => state["dealerCommitted"] || 0,
      "playerTotal" => state["playerTotal"] || 0,
      "dealerTotal" => state["dealerTotal"] || 0,
      "currentBet" => current,
      "callAmount" => call,
      "maxRaiseTo" => limit,
      "minRaiseTo" => min(current + (state["minRaise"] || @blind), limit),
      "playerBest" => state["playerBest"],
      "dealerBest" => state["dealerBest"],
      "message" => state["message"] || "Press Deal to post the blinds.",
      "net" => state["net"] || 0,
      "winner" => state["winner"],
      "canCheck" => active and call == 0,
      "canCall" => active and call > 0 and call <= balance,
      "canRaise" => active and limit > current,
      "canFold" => active
    }
  end

  defp visible_dealer(state, "settled"), do: state["dealerHole"]

  defp visible_dealer(_state, "playerTurn"),
    do: List.duplicate(%{"rank" => "A", "suit" => "spades"}, 2)

  defp visible_dealer(_state, _phase), do: []
end
