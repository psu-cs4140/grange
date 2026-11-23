defmodule Grange.AdminBootstrapTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Grange.{Accounts, AdminBootstrap}

  @keys [:env, :start_admin, :admin_username, :admin_email, :admin_password]

  setup do
    Accounts.reset()
    original = Map.new(@keys, &{&1, Application.get_env(:grange, &1)})

    on_exit(fn ->
      Enum.each(original, fn {key, value} -> Application.put_env(:grange, key, value) end)
    end)

    :ok
  end

  test "does nothing when the start_admin flag is off" do
    Application.put_env(:grange, :env, :dev)
    Application.put_env(:grange, :start_admin, false)
    set_admin_credentials()

    assert :ok = AdminBootstrap.ensure()
    assert Accounts.list_users() == []
  end

  test "creates the configured admin when explicitly enabled in development" do
    Application.put_env(:grange, :env, :dev)
    Application.put_env(:grange, :start_admin, true)
    set_admin_credentials()

    assert :ok = AdminBootstrap.ensure()
    assert [admin] = Accounts.list_users()
    assert admin.username == "root"
    assert admin.is_admin
  end

  test "never creates an administrator in production" do
    Application.put_env(:grange, :env, :prod)
    Application.put_env(:grange, :start_admin, true)
    set_admin_credentials()

    assert :ok = AdminBootstrap.ensure()
    assert Accounts.list_users() == []
  end

  test "missing credentials skip creation without raising or using defaults" do
    Application.put_env(:grange, :env, :dev)
    Application.put_env(:grange, :start_admin, true)
    Application.put_env(:grange, :admin_username, nil)
    Application.put_env(:grange, :admin_email, nil)
    Application.put_env(:grange, :admin_password, nil)

    capture_log(fn -> assert :ok = AdminBootstrap.ensure() end)
    assert Accounts.list_users() == []
  end

  test "a missing password does not fall back to a known password" do
    Application.put_env(:grange, :env, :dev)
    Application.put_env(:grange, :start_admin, true)
    Application.put_env(:grange, :admin_username, "root")
    Application.put_env(:grange, :admin_email, "root@example.test")
    Application.put_env(:grange, :admin_password, nil)

    capture_log(fn -> assert :ok = AdminBootstrap.ensure() end)
    assert Accounts.list_users() == []
  end

  defp set_admin_credentials do
    Application.put_env(:grange, :admin_username, "root")
    Application.put_env(:grange, :admin_email, "root@example.test")
    Application.put_env(:grange, :admin_password, "harvest-please")
  end
end
