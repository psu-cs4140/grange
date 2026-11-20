defmodule Grange.PokerHand do
  @moduledoc "Ranks a Hold'em hand using the best five available cards."

  @categories ~w(highCard pair twoPair trips straight flush fullHouse quads straightFlush)

  def best(cards) when length(cards) >= 5 do
    cards |> combinations(5) |> Enum.map(&score/1) |> Enum.max()
  end

  def category({rank, _tiebreakers}), do: Enum.at(@categories, rank)

  def rank(%{"rank" => "A"}), do: 14
  def rank(%{"rank" => "K"}), do: 13
  def rank(%{"rank" => "Q"}), do: 12
  def rank(%{"rank" => "J"}), do: 11
  def rank(%{"rank" => value}), do: String.to_integer(value)

  defp combinations(_cards, 0), do: [[]]
  defp combinations([], _count), do: []

  defp combinations([card | rest], count) do
    Enum.map(combinations(rest, count - 1), &[card | &1]) ++ combinations(rest, count)
  end

  defp score(cards) do
    ranks = cards |> Enum.map(&rank/1) |> Enum.sort(:desc)
    flush = cards |> Enum.uniq_by(& &1["suit"]) |> length() == 1
    straight = straight_high(ranks)

    groups =
      ranks
      |> Enum.frequencies()
      |> Enum.map(fn {rank, count} -> {count, rank} end)
      |> Enum.sort(:desc)

    classify(groups, ranks, flush, straight)
  end

  defp straight_high([14, 5, 4, 3, 2]), do: 5

  defp straight_high([a, b, c, d, e])
       when a == b + 1 and b == c + 1 and c == d + 1 and d == e + 1, do: a

  defp straight_high(_ranks), do: nil

  defp classify(_groups, _ranks, true, high) when is_integer(high), do: {8, [high]}
  defp classify([{4, four}, {1, kicker}], _, _, _), do: {7, [four, kicker]}
  defp classify([{3, three}, {2, pair}], _, _, _), do: {6, [three, pair]}
  defp classify(_, ranks, true, _), do: {5, ranks}
  defp classify(_, _, _, high) when is_integer(high), do: {4, [high]}
  defp classify([{3, three} | rest], _, _, _), do: {3, [three | kickers(rest)]}
  defp classify([{2, high}, {2, low}, {1, kicker}], _, _, _), do: {2, [high, low, kicker]}
  defp classify([{2, pair} | rest], _, _, _), do: {1, [pair | kickers(rest)]}
  defp classify(_, ranks, _, _), do: {0, ranks}

  defp kickers(groups), do: Enum.map(groups, &elem(&1, 1))
end
