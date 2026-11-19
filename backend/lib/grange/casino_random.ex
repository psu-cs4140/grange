defmodule Grange.CasinoRandom do
  @moduledoc "Unbiased draws from the system cryptographic random source."

  @spec draw(1..256) :: pos_integer()
  def draw(size) when size in 1..256 do
    <<byte>> = :crypto.strong_rand_bytes(1)
    limit = 256 - rem(256, size)

    if byte < limit do
      rem(byte, size) + 1
    else
      draw(size)
    end
  end
end
