defmodule GrangeWeb.FarmChannelAdminTest do
  @moduledoc false

  use GrangeWeb.ChannelCase

  import Grange.FarmFixtures

  alias Grange.{Accounts, Barn, FarmStore, Repo}
  alias GrangeWeb.ChannelCase, as: Helper

  setup do
    Accounts.reset()
    reset_farm_state()
    :ok
  end

  defp promote_admin(username) do
    Helper.register_user(username)
    |> Ecto.Changeset.change(is_admin: true)
    |> Repo.update!()
  end

  defp join_admin(admin, owner) do
    socket(GrangeWeb.UserSocket, admin.id, %{user: admin})
    |> subscribe_and_join(GrangeWeb.FarmChannel, "farm:#{owner}")
  end

  test "a forged admin flag on the socket cannot join a private farm" do
    full_farm("Alice")
    user = Helper.register_user("Mallory")
    forged = %{user | is_admin: true}

    assert {:error, %{error: "farm is private"}} =
             socket(GrangeWeb.UserSocket, user.id, %{user: forged})
             |> subscribe_and_join(GrangeWeb.FarmChannel, "farm:Alice")
  end

  test "a real administrator may join a private farm" do
    full_farm("Alice")
    admin = promote_admin("Root")

    assert {:ok, reply, _socket} = join_admin(admin, "Alice")
    assert reply.farm.owner == "Alice"
  end

  test "a forged admin flag on the socket cannot move props" do
    public_farm("Alice")
    user = Helper.register_user("Mallory")
    forged = %{user | is_admin: true}

    {:ok, _reply, socket} =
      socket(GrangeWeb.UserSocket, user.id, %{user: forged})
      |> subscribe_and_join(GrangeWeb.FarmChannel, "farm:Alice")

    ref = push(socket, "farmPropAction", %{"action" => %{"kind" => "dig", "index" => 2}})
    assert_reply(ref, :error, %{error: "not your farm"})
    refute Enum.any?(FarmStore.view("Alice").prop_overrides, &(&1.index == 2 and &1.carried))
  end

  test "an administrator cannot sell another player's produce" do
    full_farm("Alice")
    Barn.add("Alice", "tomato", 2)
    admin = promote_admin("Root")
    {:ok, _reply, socket} = join_admin(admin, "Alice")

    ref = push(socket, "sellProduce", %{"item" => "tomato", "count" => 1})
    assert_reply(ref, :error, %{error: "not your farm"})
    assert Barn.map("Alice")["tomato"] == 2
  end

  test "an administrator cannot change another player's farm settings" do
    full_farm("Alice")
    admin = promote_admin("Root")
    {:ok, _reply, socket} = join_admin(admin, "Alice")

    ref = push(socket, "updateSettings", %{"is_public" => true})
    assert_reply(ref, :error, %{error: "not your farm"})
    refute FarmStore.view("Alice").is_public
  end
end
