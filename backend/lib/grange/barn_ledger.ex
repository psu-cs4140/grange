defmodule Grange.BarnLedger do
  @moduledoc """
  Moves a barn-storage stack into and out of the container that owns it.

  Barn storage is not a second copy of an item. A deposit takes the stack out of
  the ledger that authoritatively holds it (the seed/material ledger, the barn's
  produce, personal items, livestock, or farm supplies) and a withdrawal puts it
  back. Without that transfer the client's mirrors would re-add a stored stack to
  the inventory, and the server could spend a stack while it sat in storage.

  Placed buildings and decor are refused: their `farm_props` row records where
  they stand, so they cannot leave the farm without losing that spot.
  """

  alias Grange.{Barn, FarmRecord, Inventory, PlayerItems, Repo}

  # Account ledgers bought at the market and spent by farming, building, and
  # the realtor.
  @ledger_items ~w(seed-bag wheat-seed lettuce-seed midas-wheat-seed frost-lettuce-seed
                   sunburst-tomato-seed wood-plank stone nails)

  # Finished produce and drinks, which live in `barn_items`.
  @produce_items ~w(tomato wheat lettuce midas_wheat frost_lettuce sunburst_tomato
                    beer tomato_juice lettuce_juice)

  # Durable personal items, which live in `player_items`.
  @rod_items ~w(bamboo fiberglass carbon master)
  @fish_items ~w(minnow bluegill carp catfish trout salmon golden-carp phishing
                 loan-sharks-brother)

  @animal_items ~w(cow hen sheep pig)
  @supply_items %{"fence" => :fence_count, "gate" => :gate_count, "sprinkler" => :sprinkler_count}

  @prop_items ~w(farmhouse barn well bench sign barrel crate oak-tree pine-tree
                 apple-tree daisies marigolds blue-flowers brewery)

  @doc "Whether a barn deposit may hold `item`."
  @spec storable?(String.t()) :: boolean()
  def storable?(item), do: item not in @prop_items

  @doc "Removes `count` of `item` from the container that owns it."
  @spec take(String.t(), String.t(), integer()) :: :ok | {:error, String.t()}
  def take(owner, item, count) when item in @ledger_items, do: Inventory.take(owner, item, count)
  def take(owner, item, count) when item in @produce_items, do: Barn.remove(owner, item, count)

  def take(owner, item, count) when item in @rod_items or item in @fish_items,
    do: PlayerItems.remove(owner, item, count)

  def take(owner, item, count) when item in @animal_items, do: change_animal(owner, item, -count)

  def take(owner, item, count) when is_map_key(@supply_items, item),
    do: change_supply(owner, item, -count)

  # Tools have no server ledger; their slot in the saved layout is the record.
  def take(_owner, _item, _count), do: :ok

  @doc "Returns `count` of `item` to the container that owns it."
  @spec give(String.t(), String.t(), integer()) :: :ok | {:error, String.t()}
  def give(owner, item, count) when item in @ledger_items, do: Inventory.add(owner, item, count)
  def give(owner, item, count) when item in @produce_items, do: Barn.add(owner, item, count)

  def give(owner, item, count) when item in @rod_items or item in @fish_items,
    do: PlayerItems.add(owner, item, count)

  def give(owner, item, count) when item in @animal_items, do: change_animal(owner, item, count)

  def give(owner, item, count) when is_map_key(@supply_items, item),
    do: change_supply(owner, item, count)

  def give(_owner, _item, _count), do: :ok

  defp change_animal(owner, item, delta) do
    farm = Repo.get!(FarmRecord, owner)
    next = Map.get(farm.animals, item, 0) + delta

    if next < 0 do
      {:error, "not enough #{item}"}
    else
      farm
      |> Ecto.Changeset.change(animals: Map.put(farm.animals, item, next))
      |> Repo.update!()

      :ok
    end
  end

  defp change_supply(owner, item, delta) do
    field = Map.fetch!(@supply_items, item)
    farm = Repo.get!(FarmRecord, owner)
    next = Map.fetch!(farm, field) + delta

    if next < 0 do
      {:error, "not enough #{item}"}
    else
      farm
      |> Ecto.Changeset.change(%{field => next})
      |> Repo.update!()

      :ok
    end
  end
end
