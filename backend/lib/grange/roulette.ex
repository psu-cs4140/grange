defmodule Grange.Roulette do
  @moduledoc "Validates American roulette bets and settles a server-drawn pocket."

  alias Grange.{CasinoRandom, SlotSpins}

  @red [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
  @pockets ["0", "00" | Enum.map(1..36, &Integer.to_string/1)]
  @gross %{1 => 36, 2 => 18, 3 => 12, 4 => 9, 5 => 7, 6 => 6, 12 => 3, 18 => 2}

  def spin(user_id, id, bets) when is_map(bets) and map_size(bets) in 1..200 do
    with {:ok, resolved} <- resolve(bets) do
      stake = Enum.sum(Enum.map(resolved, fn {amount, _numbers} -> amount end))

      SlotSpins.settle_round(user_id, id, stake, %{"game" => "roulette", "bets" => bets}, fn ->
        draw(resolved)
      end)
    end
  end

  def spin(_user_id, _id, _bets), do: {:error, :invalid_spin}

  defp draw(bets) do
    pocket = Enum.at(@pockets, CasinoRandom.draw(length(@pockets)) - 1)
    payout = Enum.sum(Enum.map(bets, &return_for(&1, pocket)))
    %{"pocket" => pocket, "payout" => payout}
  end

  defp return_for({amount, numbers}, pocket) do
    if pocket in numbers, do: amount * Map.fetch!(@gross, length(numbers)), else: 0
  end

  defp resolve(bets) do
    Enum.reduce_while(bets, {:ok, []}, fn
      {spot, amount}, {:ok, acc} when is_integer(amount) and amount in 1..1_000_000_000 ->
        case numbers(String.split(spot, ":")) do
          [] -> {:halt, {:error, :invalid_spin}}
          pockets -> {:cont, {:ok, [{amount, pockets} | acc]}}
        end

      _invalid, _acc ->
        {:halt, {:error, :invalid_spin}}
    end)
  end

  defp numbers(["n", pocket]) when pocket in @pockets, do: [pocket]
  defp numbers(["five", "0"]), do: ["0", "00", "1", "2", "3"]
  defp numbers(["outside", "low"]), do: strings(1..18)
  defp numbers(["outside", "high"]), do: strings(19..36)
  defp numbers(["outside", "odd"]), do: strings(1..35//2)
  defp numbers(["outside", "even"]), do: strings(2..36//2)
  defp numbers(["outside", "red"]), do: strings(@red)
  defp numbers(["outside", "black"]), do: strings(Enum.reject(1..36, &(&1 in @red)))

  defp numbers(["split-g", a, b])
       when {a, b} in [
              {"0", "3"},
              {"0", "2"},
              {"00", "2"},
              {"00", "1"},
              {"0", "00"}
            ],
       do: [a, b]

  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp numbers([kind, index]) do
    case {kind, Integer.parse(index)} do
      {"street", {col, ""}} when col in 0..11 -> grid([col], 0..2)
      {"line", {col, ""}} when col in 0..10 -> grid(col..(col + 1), 0..2)
      {"column", {row, ""}} when row in 0..2 -> grid(0..11, [row])
      {"dozen", {i, ""}} when i in 0..2 -> strings((i * 12 + 1)..(i * 12 + 12))
      _invalid -> []
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp numbers([kind, column, row]) do
    case {kind, Integer.parse(column), Integer.parse(row)} do
      {"split-h", {c, ""}, {r, ""}} when c in 0..10 and r in 0..2 -> grid(c..(c + 1), [r])
      {"split-v", {c, ""}, {r, ""}} when c in 0..11 and r in 0..1 -> grid([c], r..(r + 1))
      {"corner", {c, ""}, {r, ""}} when c in 0..10 and r in 0..1 -> grid(c..(c + 1), r..(r + 1))
      _invalid -> []
    end
  end

  defp numbers(_invalid), do: []

  defp grid(cols, rows),
    do: for(col <- cols, row <- rows, do: Integer.to_string(3 - row + col * 3))

  defp strings(numbers), do: Enum.map(numbers, &Integer.to_string/1)
end
