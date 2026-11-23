defmodule Grange.BarnStorage do
  @moduledoc """
  The barn's storage container: a map of item id to a stored count.

  The barn holds arbitrary item stacks rather than the field's crop total.
  Counts are capped per item, and the number of distinct items is capped, so
  the client can render one slot per stored item. Every accepted change is a
  single `farms.storage` write, so deposits and withdrawals persist across
  restarts.

  A deposit also takes the stack out of the container that authoritatively owns
  it, and a withdrawal returns it (`Grange.BarnLedger`). Storage is therefore a
  move, never a copy: the client's inventory mirrors cannot re-add a stored
  stack, and a stored stack cannot be spent by another action.
  """

  alias Grange.{BarnLedger, FarmRecord, Repo}

  @max_per_item 999
  @max_distinct 24
  @item_format ~r/^[a-z0-9-]{1,32}$/

  @type storage :: %{optional(String.t()) => pos_integer()}

  @doc "The stored map for a farm struct, or an empty map when there is none."
  @spec inventory(FarmRecord.t() | nil) :: storage()
  def inventory(nil), do: %{}
  def inventory(%FarmRecord{storage: storage}), do: storage || %{}

  @doc """
  Applies a `deposit` or `withdraw` for one item.

  Returns `{:ok, :ok}` on success so the caller owns broadcasting and the
  response view.
  """
  @spec action(String.t(), map()) :: {:ok, :ok} | {:error, String.t()}
  def action(owner, %{"kind" => kind, "item" => item, "count" => count})
      when kind in ["deposit", "withdraw"] do
    with :ok <- validate(kind, item, count) do
      transact(owner, kind, item, count)
    end
  end

  def action(_owner, _action), do: {:error, "invalid barn action"}

  defp validate(kind, item, count) do
    cond do
      not is_binary(item) or not Regex.match?(@item_format, item) ->
        {:error, "invalid item"}

      not is_integer(count) or count < 1 or count > @max_per_item ->
        {:error, "invalid count"}

      kind == "deposit" and not BarnLedger.storable?(item) ->
        {:error, "buildings stay on the farm"}

      true ->
        :ok
    end
  end

  defp transact(owner, kind, item, count) do
    case Repo.transaction(fn -> commit(owner, kind, item, count) end) do
      {:ok, :ok} -> {:ok, :ok}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, _reason} -> {:error, "could not update the barn"}
    end
  end

  defp commit(owner, kind, item, count) do
    case Repo.get(FarmRecord, owner) do
      nil ->
        Repo.rollback("farm not found")

      farm ->
        with {:ok, next} <- move(inventory(farm), kind, item, count),
             :ok <- transfer(owner, kind, item, count) do
          farm
          |> Ecto.Changeset.change(storage: next)
          |> Repo.update!()

          :ok
        else
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp transfer(owner, "deposit", item, count), do: BarnLedger.take(owner, item, count)
  defp transfer(owner, "withdraw", item, count), do: BarnLedger.give(owner, item, count)

  defp move(storage, "deposit", item, count) do
    current = Map.get(storage, item, 0)

    cond do
      current + count > @max_per_item -> {:error, "the barn is full"}
      current == 0 and map_size(storage) >= @max_distinct -> {:error, "the barn is full"}
      true -> {:ok, Map.put(storage, item, current + count)}
    end
  end

  defp move(storage, "withdraw", item, count) do
    current = Map.get(storage, item, 0)

    if current >= count do
      remaining = current - count

      next =
        if remaining == 0,
          do: Map.delete(storage, item),
          else: Map.put(storage, item, remaining)

      {:ok, next}
    else
      {:error, "not enough in the barn"}
    end
  end
end
