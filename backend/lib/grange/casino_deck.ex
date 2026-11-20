defmodule Grange.CasinoDeck do
  @moduledoc "A private shuffled deck shared by the server-side card games."

  alias Grange.CasinoRandom

  @ranks ~w(A 2 3 4 5 6 7 8 9 10 J Q K)
  @suits ~w(hearts diamonds clubs spades)

  def shuffled do
    cards = for suit <- @suits, rank <- @ranks, do: %{"rank" => rank, "suit" => suit}
    shuffle(cards, [])
  end

  defp shuffle([], drawn), do: drawn

  defp shuffle(cards, drawn) do
    {card, remaining} = List.pop_at(cards, CasinoRandom.draw(length(cards)) - 1)
    shuffle(remaining, [card | drawn])
  end
end
