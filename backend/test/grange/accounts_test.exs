defmodule Grange.AccountsTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Grange.Accounts

  setup do
    Accounts.reset()
    :ok
  end

  defp register(attrs \\ %{}) do
    Accounts.register(
      Map.merge(
        %{
          "username" => "Alice",
          "email" => "alice@example.test",
          "password" => "harvest-please"
        },
        attrs
      )
    )
  end

  test "registers a user and hides the password hash in JSON" do
    assert {:ok, user} = register()
    assert user.username == "Alice"
    assert user.email == "alice@example.test"
    refute Map.has_key?(Jason.encode!(user) |> Jason.decode!(), "password_hash")
  end

  test "rejects invalid usernames, emails, and short passwords" do
    assert {:error, message} = register(%{"username" => "ab"})
    assert message =~ "3-32"

    assert {:error, message} = register(%{"email" => "nope"})
    assert message =~ "valid email"

    assert {:error, message} = register(%{"password" => "short"})
    assert message =~ "at least 8"
  end

  test "rejects duplicate usernames and emails" do
    assert {:ok, _user} = register()

    assert {:error, "that username is taken"} =
             register(%{"email" => "other@example.test"})

    assert {:error, "that email is already registered"} =
             register(%{"username" => "Bob"})
  end

  test "authenticates with the right password only" do
    {:ok, user} = register()

    assert {:ok, ^user} = Accounts.authenticate("Alice", "harvest-please")
    assert {:error, "invalid username or password"} = Accounts.authenticate("Alice", "wrong")
    assert {:error, "invalid username or password"} = Accounts.authenticate("Nobody", "whatever")
  end

  test "session tokens resolve to the user and can be destroyed" do
    {:ok, user} = register()
    token = Accounts.create_session(user.id)

    assert {:ok, ^user} = Accounts.resolve_token(token)
    assert :error = Accounts.resolve_token(nil)
    assert :error = Accounts.resolve_token("bogus")

    assert :ok = Accounts.destroy_session(token)
    assert :error = Accounts.resolve_token(token)
  end

  test "list_users is sorted and reset clears everything" do
    {:ok, _} = register(%{"username" => "Charlie", "email" => "c@example.test"})
    {:ok, _} = register(%{"username" => "Alice", "email" => "a@example.test"})

    assert Enum.map(Accounts.list_users(), & &1.username) == ["Alice", "Charlie"]

    assert :ok = Accounts.reset()
    assert Accounts.list_users() == []
  end

  test "new users start at the opening balance, included in JSON" do
    assert {:ok, user} = register()
    assert user.balance == 100

    decoded = user |> Jason.encode!() |> Jason.decode!()
    assert decoded["balance"] == 100
  end

  test "new users are not admins, and is_admin is included in JSON" do
    assert {:ok, user} = register()
    refute user.is_admin

    decoded = user |> Jason.encode!() |> Jason.decode!()
    assert decoded["is_admin"] == false
  end

  test "apply_balance_delta spends, earns, and clamps at zero" do
    {:ok, user} = register()

    assert {:ok, 70} = Accounts.apply_balance_delta(user.id, -30)
    assert {:ok, 75} = Accounts.apply_balance_delta(user.id, 5)
    assert {:ok, 0} = Accounts.apply_balance_delta(user.id, -1_000)

    stored = Enum.find(Accounts.list_users(), &(&1.id == user.id))
    assert stored.balance == 0
  end

  test "apply_balance_delta rejects bad deltas and unknown users" do
    {:ok, user} = register()

    assert {:error, _} = Accounts.apply_balance_delta(user.id, "loot")
    assert {:error, _} = Accounts.apply_balance_delta(user.id, 1.5)
    assert {:error, _} = Accounts.apply_balance_delta("missing", 10)
  end

  test "register_admin creates an admin with an effectively unlimited balance" do
    assert {:ok, user} =
             Accounts.register_admin(%{
               "username" => "Root",
               "email" => "root@example.test",
               "password" => "harvest-please"
             })

    assert user.is_admin
    assert user.balance == 1_000_000_000

    decoded = user |> Jason.encode!() |> Jason.decode!()
    assert decoded["is_admin"] == true
    assert decoded["balance"] == 1_000_000_000
  end

  test "admins never spend down their balance, but can still earn" do
    {:ok, user} =
      Accounts.register_admin(%{
        "username" => "Root",
        "email" => "root@example.test",
        "password" => "harvest-please"
      })

    assert {:ok, 1_000_000_000} = Accounts.apply_balance_delta(user.id, -500)
    assert {:ok, 1_000_000_050} = Accounts.apply_balance_delta(user.id, 50)
  end

  test "grant_admin promotes an existing account and tops up its balance" do
    {:ok, user} = register()
    refute user.is_admin

    assert {:ok, promoted} = Accounts.grant_admin("Alice")
    assert promoted.id == user.id
    assert promoted.is_admin
    assert promoted.balance == 1_000_000_000

    assert {:error, "unknown user"} = Accounts.grant_admin("Nobody")
  end

  test "grant_admin can reset the password so the login is known" do
    {:ok, _user} = register()

    assert {:ok, promoted} = Accounts.grant_admin("Alice", "brand-new-pass")
    assert promoted.is_admin

    assert {:ok, _} = Accounts.authenticate("Alice", "brand-new-pass")
    assert {:error, _} = Accounts.authenticate("Alice", "harvest-please")
  end

  describe "ensure_admin" do
    setup do
      keys = [:admin_username, :admin_email, :admin_password]
      original = Map.new(keys, &{&1, Application.get_env(:grange, &1)})

      on_exit(fn ->
        Enum.each(original, fn {key, value} -> Application.put_env(:grange, key, value) end)
      end)

      :ok
    end

    test "creates the configured admin account idempotently" do
      set_admin_credentials("root", "root@example.test", "harvest-please")

      assert {:ok, admin} = Accounts.ensure_admin()
      assert admin.username == "root"
      assert admin.email == "root@example.test"
      assert admin.is_admin
      assert Accounts.admin?(admin.id)

      assert {:ok, again} = Accounts.ensure_admin()
      assert again.id == admin.id
    end

    test "refuses to invent credentials when none are configured" do
      clear_admin_credentials()

      assert {:error, message} = Accounts.ensure_admin()
      assert message =~ "not configured"
      assert Accounts.list_users() == []
    end

    test "never falls back to the old default admin login" do
      clear_admin_credentials()

      assert {:error, _message} = Accounts.ensure_admin()
      refute Enum.any?(Accounts.list_users(), &(&1.username == "admin"))
    end

    test "does not promote an account that only matches the configured email" do
      assert {:ok, user} =
               register(%{"username" => "Mallory", "email" => "root@example.test"})

      set_admin_credentials("root", "root@example.test", "harvest-please")

      assert {:error, message} = Accounts.ensure_admin()
      assert message =~ "email already belongs"
      refute reload(user.id).is_admin
    end

    test "does not promote a username squatter with a different email" do
      assert {:ok, user} =
               register(%{"username" => "root", "email" => "mallory@example.test"})

      set_admin_credentials("root", "root@example.test", "harvest-please")

      assert {:error, message} = Accounts.ensure_admin()
      assert message =~ "belongs to another account"
      refute reload(user.id).is_admin
    end

    test "promotes the existing account when username and email both match" do
      assert {:ok, user} =
               register(%{"username" => "root", "email" => "root@example.test"})

      set_admin_credentials("root", "root@example.test", "harvest-please")

      assert {:ok, admin} = Accounts.ensure_admin()
      assert admin.id == user.id
      assert admin.is_admin
      assert {:ok, _} = Accounts.authenticate("root", "harvest-please")
    end
  end

  test "registration cannot request administrator privileges" do
    assert {:ok, user} = register(%{"is_admin" => true})
    refute user.is_admin
    refute Accounts.admin?(user.id)
  end

  defp set_admin_credentials(username, email, password) do
    Application.put_env(:grange, :admin_username, username)
    Application.put_env(:grange, :admin_email, email)
    Application.put_env(:grange, :admin_password, password)
  end

  defp clear_admin_credentials do
    Application.put_env(:grange, :admin_username, nil)
    Application.put_env(:grange, :admin_email, nil)
    Application.put_env(:grange, :admin_password, nil)
  end

  defp reload(id), do: Enum.find(Accounts.list_users(), &(&1.id == id))
end
