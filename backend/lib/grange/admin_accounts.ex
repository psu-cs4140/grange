defmodule Grange.AdminAccounts do
  @moduledoc """
  Ensures the operator-configured administrator account exists.

  Credentials come from `:admin_username`, `:admin_email`, and `:admin_password`
  app configuration (the `GRANGE_ADMIN_*` environment variables in dev). There
  is no built-in default; when any value is missing this returns an error and
  leaves every account untouched, so startup can log a warning and continue.

  The account is identified by username only. An existing account is promoted
  only when its email also matches the configured administrator email, so
  taking the username alone cannot grant admin rights. A configured email that
  already belongs to another account is never touched.
  """

  alias Grange.{Accounts, Repo, User}

  @doc "Ensures the configured administrator exists, or explains why it cannot."
  @spec ensure_admin() :: {:ok, User.t()} | {:error, String.t()}
  def ensure_admin do
    with {:ok, username} <- admin_setting(:admin_username),
         {:ok, email} <- admin_setting(:admin_email),
         {:ok, password} <- admin_setting(:admin_password) do
      ensure_admin(%{"username" => username, "email" => email, "password" => password})
    end
  end

  @doc false
  @spec ensure_admin(map()) :: {:ok, User.t()} | {:error, String.t()}
  def ensure_admin(attrs) do
    username = attrs |> fetch(:username) |> String.trim()
    email = attrs |> fetch(:email) |> String.trim() |> String.downcase()
    password = fetch(attrs, :password)

    case Repo.get_by(User, username: username) do
      nil -> create_configured_admin(username, email, password)
      %User{} = user -> promote_configured_admin(user, email, password)
    end
  end

  defp create_configured_admin(username, email, password) do
    case Repo.get_by(User, email: email) do
      nil ->
        Accounts.register_admin(%{
          "username" => username,
          "email" => email,
          "password" => password
        })

      %User{} = other ->
        {:error, "admin email already belongs to #{other.username}"}
    end
  end

  # Promoting an existing account is safe only when the configured admin email
  # also matches, which proves this is the account the operator configured. A
  # user who merely grabbed the username is left untouched.
  defp promote_configured_admin(%User{email: email} = user, email, password) do
    Accounts.grant_admin(user.username, password)
  end

  defp promote_configured_admin(%User{}, _email, _password) do
    {:error, "configured admin username belongs to another account"}
  end

  defp admin_setting(key) do
    case Application.get_env(:grange, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "#{key} is not configured"}
    end
  end

  defp fetch(attrs, key) when is_map(attrs) do
    Map.get(attrs, to_string(key)) || Map.get(attrs, key) || ""
  end
end
