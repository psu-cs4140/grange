defmodule Grange.BarnStorageTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Grange.{Barn, BarnStorage, FarmRecord, FarmStore, Inventory, PlayerItems, Repo}

  setup do
    FarmStore.reset()
    :ok
  end

  defp action(kind, item, count) do
    with {:ok, :ok} <-
           BarnStorage.action("Alice", %{"kind" => kind, "item" => item, "count" => count}) do
      FarmStore.refresh("Alice")
    end
  end

  test "a new farm has an empty barn" do
    assert FarmStore.ensure("Alice").storage == %{}
    assert BarnStorage.inventory(nil) == %{}
  end

  test "deposits stack by item and persist in the farm view" do
    FarmStore.ensure("Alice")
    Barn.add("Alice", "tomato", 5)

    assert {:ok, view} = action("deposit", "tomato", 3)
    assert view.storage == %{"tomato" => 3}

    assert {:ok, view} = action("deposit", "tomato", 2)
    assert view.storage == %{"tomato" => 5}
    assert FarmStore.view("Alice").storage == %{"tomato" => 5}
  end

  test "withdrawals remove stored items and clear empty entries" do
    FarmStore.ensure("Alice")
    action("deposit", "seed-bag", 10)

    assert {:ok, view} = action("withdraw", "seed-bag", 4)
    assert view.storage == %{"seed-bag" => 6}

    assert {:ok, view} = action("withdraw", "seed-bag", 6)
    assert view.storage == %{}
  end

  test "withdrawing more than the barn holds is rejected" do
    FarmStore.ensure("Alice")
    Barn.add("Alice", "tomato", 2)
    action("deposit", "tomato", 2)

    assert {:error, "not enough in the barn"} = action("withdraw", "tomato", 3)
    assert FarmStore.view("Alice").storage == %{"tomato" => 2}
  end

  test "invalid items and counts are rejected" do
    FarmStore.ensure("Alice")

    assert {:error, "invalid item"} = action("deposit", "Tomato", 1)
    assert {:error, "invalid item"} = action("deposit", "", 1)
    assert {:error, "invalid count"} = action("deposit", "tomato", 0)
    assert {:error, "invalid count"} = action("deposit", "tomato", -1)
    assert {:error, "invalid count"} = action("deposit", "tomato", 1000)
    assert {:error, "invalid barn action"} = action("drop", "tomato", 1)
    assert FarmStore.view("Alice").storage == %{}
  end

  test "the barn caps each item and the number of distinct items" do
    FarmStore.ensure("Alice")
    Barn.add("Alice", "tomato", 999)

    assert {:ok, _} = action("deposit", "tomato", 999)
    assert {:error, "the barn is full"} = action("deposit", "tomato", 1)

    for index <- 1..23 do
      assert {:ok, _} = action("deposit", "item-#{index}", 1)
    end

    # 24 distinct items (tomato plus 23) fill the barn; a new item is refused.
    assert map_size(FarmStore.view("Alice").storage) == 24
    assert {:error, "the barn is full"} = action("deposit", "item-24", 1)
  end

  test "actions on a missing farm are rejected" do
    assert {:error, "farm not found"} =
             BarnStorage.action("Nobody", %{
               "kind" => "deposit",
               "item" => "tomato",
               "count" => 1
             })
  end

  describe "stored stacks are moved, not copied" do
    test "a deposited seed leaves the account ledger" do
      FarmStore.ensure("Alice")
      assert Inventory.holdings("Alice")["seed-bag"] == 10

      assert {:ok, view} = action("deposit", "seed-bag", 10)
      assert view.storage == %{"seed-bag" => 10}
      # The ledger no longer holds the seeds, so a reload cannot re-add them.
      assert Inventory.holdings("Alice")["seed-bag"] == 0

      assert {:ok, view} = action("withdraw", "seed-bag", 10)
      assert view.storage == %{}
      assert Inventory.holdings("Alice")["seed-bag"] == 10
    end

    test "a deposited crop leaves the barn and returns on withdrawal" do
      FarmStore.ensure("Alice")
      Barn.add("Alice", "tomato", 4)

      assert {:ok, view} = action("deposit", "tomato", 4)
      assert view.storage == %{"tomato" => 4}
      assert Map.get(view.barn, "tomato", 0) == 0

      assert {:ok, view} = action("withdraw", "tomato", 4)
      assert view.storage == %{}
      assert view.barn["tomato"] == 4
    end

    test "a deposited fish leaves the player's creel" do
      FarmStore.ensure("Alice")
      PlayerItems.add("Alice", "minnow", 3)

      assert {:ok, _view} = action("deposit", "minnow", 3)
      assert PlayerItems.map("Alice")["minnow"] == 0

      assert {:ok, _view} = action("withdraw", "minnow", 3)
      assert PlayerItems.map("Alice")["minnow"] == 3
    end

    test "a deposited animal leaves the farm's livestock count" do
      FarmStore.ensure("Alice")
      farm = Repo.get!(FarmRecord, "Alice")
      Repo.update!(Ecto.Changeset.change(farm, animals: %{"cow" => 2}))

      assert {:ok, view} = action("deposit", "cow", 2)
      assert view.animals == %{"cow" => 0}
      assert view.storage == %{"cow" => 2}

      assert {:ok, view} = action("withdraw", "cow", 2)
      assert view.animals == %{"cow" => 2}
      assert view.storage == %{}
    end

    test "a deposited fence spends the farm's supply" do
      FarmStore.ensure("Alice")

      assert {:ok, view} = action("deposit", "fence", 2)
      assert view.fence_count == 18
      assert view.storage == %{"fence" => 2}

      assert {:ok, view} = action("withdraw", "fence", 2)
      assert view.fence_count == 20
      assert view.storage == %{}
    end

    test "depositing more than the source holds is rejected without a write" do
      FarmStore.ensure("Alice")
      Barn.add("Alice", "tomato", 2)

      assert {:error, "not enough tomato"} = action("deposit", "tomato", 3)
      assert FarmStore.view("Alice").storage == %{}
      assert FarmStore.view("Alice").barn["tomato"] == 2
    end

    test "placed buildings stay on the farm" do
      FarmStore.ensure("Alice")

      assert {:error, "buildings stay on the farm"} = action("deposit", "barn", 1)
      assert FarmStore.view("Alice").storage == %{}
    end
  end
end
