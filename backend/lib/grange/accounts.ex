defmodule Grange.Accounts do
  @moduledoc """
  Accounts and sessions, persisted in the database.

  Validation messages match the previous in-memory implementation so the SPA
  and tests see the same contract. Session tokens are handed to the client as
  opaque strings; only a SHA-256 hash is stored, so a database leak cannot be
  replayed.
  """

  import Ecto.Query

  alias Grange.{Repo, Session, User}

  @username_re ~r/^[a-zA-Z0-9_-]{3,32}$/
  @email_re ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  @min_password 8
  @token_bytes 32
  @ttl_seconds 30 * 24 * 60 * 60
  @lobby_topic "lobby"
  # Admins are seeded with a balance large enough to read as "unlimited" for
  # any in-game price; debits against it are ignored (see apply_balance_delta/2).
  @admin_balance 1_000_000_000

  @spec register(map()) :: {:ok, User.t()} | {:error, String.t()}
  def register(attrs) do
    username = attrs |> fetch(:username) |> String.trim()
    email = attrs |> fetch(:email) |> String.trim() |> String.downcase()
    password = fetch(attrs, :password)

    with :ok <- validate_username(username),
         :ok <- validate_email(email),
         :ok <- validate_password(password),
         :ok <- ensure_unique(username, email) do
      insert_user(username, email, password)
    end
  end

  @spec authenticate(String.t(), String.t()) :: {:ok, User.t()} | {:error, String.t()}
  def authenticate(username, password) do
    case Repo.get_by(User, username: username) do
      nil ->
        # Hash anyway so a missing account takes the same time as a wrong password.
        _ = hash(password)
        {:error, "invalid username or password"}

      %User{} = user ->
        if Argon2.verify_pass(password, user.password_hash) do
          {:ok, user}
        else
          {:error, "invalid username or password"}
        end
    end
  end

  @spec create_session(String.t()) :: String.t()
  def create_session(user_id) do
    token = :crypto.strong_rand_bytes(@token_bytes) |> Base.url_encode64(padding: false)

    %Session{
      token_hash: hash_token(token),
      user_id: user_id,
      expires_at: DateTime.add(DateTime.utc_now(), @ttl_seconds, :second)
    }
    |> Repo.insert!()

    token
  end

  @spec resolve_token(String.t() | nil) :: {:ok, User.t()} | :error
  def resolve_token(token) when token in [nil, ""], do: :error

  def resolve_token(token) do
    case Repo.get(Session, hash_token(token)) do
      nil -> :error
      session -> resolve_session(session)
    end
  end

  @spec destroy_session(String.t() | nil) :: :ok
  def destroy_session(token) when token in [nil, ""], do: :ok

  def destroy_session(token) do
    Repo.delete_all(from(s in Session, where: s.token_hash == ^hash_token(token)))
    :ok
  end

  @spec list_users() :: [User.t()]
  def list_users, do: Repo.all(from(u in User, order_by: u.username))

  @spec apply_balance_delta(String.t(), integer()) ::
          {:ok, non_neg_integer()} | {:error, String.t()}
  def apply_balance_delta(user_id, delta) when is_integer(delta) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, "unknown user"}

      %User{is_admin: true} = user when delta < 0 ->
        # Admins draw on effective infinity: a debit never lowers the balance.
        {:ok, user.balance}

      %User{} = user ->
        # Spend/earn delta, clamped at zero so a balance can never go negative.
        balance = max(0, user.balance + delta)
        user |> Ecto.Changeset.change(balance: balance) |> Repo.update!()
        {:ok, balance}
    end
  end

  def apply_balance_delta(_user_id, _delta), do: {:error, "delta must be an integer"}

  @doc """
  Registers an account and promotes it to admin.

  Admins are handed the whole item catalog by the SPA and are given a balance
  large enough to be effectively unlimited. Used by `mix grange.create_admin`.
  """
  @spec register_admin(map()) :: {:ok, User.t()} | {:error, String.t()}
  def register_admin(attrs) do
    case register(attrs) do
      {:ok, user} -> promote(user, nil)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Promotes an existing account to admin by username."
  @spec grant_admin(String.t()) :: {:ok, User.t()} | {:error, String.t()}
  def grant_admin(username), do: grant_admin(username, nil)

  @doc """
  Promotes an existing account to admin, optionally resetting its password so
  the operator always ends up with a login they know.
  """
  @spec grant_admin(String.t(), String.t() | nil) :: {:ok, User.t()} | {:error, String.t()}
  def grant_admin(username, password) do
    with :ok <- validate_optional_password(password) do
      case Repo.get_by(User, username: username) do
        nil -> {:error, "unknown user"}
        %User{} = user -> promote(user, password)
      end
    end
  end

  @doc """
  True when the given account id belongs to a current administrator.

  Callers should use this instead of trusting an `is_admin` value copied onto a
  socket, token, or client payload.
  """
  @spec admin?(String.t() | nil) :: boolean()
  def admin?(user_id) when is_binary(user_id) do
    Repo.exists?(from(u in User, where: u.id == ^user_id and u.is_admin == true))
  end

  def admin?(_user_id), do: false

  @doc """
  Ensures the configured administrator account exists.

  Credentials come from `:admin_username`, `:admin_email`, and `:admin_password`
  app configuration (the `GRANGE_ADMIN_*` environment variables in dev). There
  is no built-in default; when any value is missing this returns an error and
  leaves every account untouched, so startup can log a warning and continue.

  The account is identified by username only. An existing account is promoted
  only when its email also matches the configured administrator email, so
  taking the username alone cannot grant admin rights. A configured email that
  already belongs to another account is never touched.
  """
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

  @spec reset() :: :ok
  def reset do
    Repo.delete_all(Session)
    Repo.delete_all(User)
    :ok
  end

  defp resolve_session(session) do
    if DateTime.compare(DateTime.utc_now(), session.expires_at) == :lt do
      case Repo.get(User, session.user_id) do
        nil -> :error
        user -> {:ok, user}
      end
    else
      Repo.delete(session)
      :error
    end
  end

  defp insert_user(username, email, password) do
    attrs = %{username: username, email: email, password_hash: hash(password)}

    case %User{id: User.id()} |> User.changeset(attrs) |> Repo.insert() do
      {:ok, user} ->
        broadcast_players()
        {:ok, user}

      {:error, changeset} ->
        {:error, error_message(changeset)}
    end
  end

  # Grants admin rights and tops the balance up to the admin floor. Promotion
  # only ever raises the balance, so promoting an account never takes money away.
  # A password, when given, is rehashed and stored so the login is known.
  defp promote(user, password) do
    balance = max(user.balance, @admin_balance)

    changes =
      if password do
        %{is_admin: true, balance: balance, password_hash: hash(password)}
      else
        %{is_admin: true, balance: balance}
      end

    case user |> Ecto.Changeset.change(changes) |> Repo.update() do
      {:ok, user} -> {:ok, user}
      {:error, changeset} -> {:error, error_message(changeset)}
    end
  end

  defp error_message(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {_field, {message, _opts}} -> message end)
  end

  defp ensure_unique(username, email) do
    cond do
      Repo.exists?(from(u in User, where: u.username == ^username)) ->
        {:error, "that username is taken"}

      Repo.exists?(from(u in User, where: u.email == ^email)) ->
        {:error, "that email is already registered"}

      true ->
        :ok
    end
  end

  defp create_configured_admin(username, email, password) do
    case Repo.get_by(User, email: email) do
      nil ->
        register_admin(%{"username" => username, "email" => email, "password" => password})

      %User{} = other ->
        {:error, "admin email already belongs to #{other.username}"}
    end
  end

  # Promoting an existing account is safe only when the configured admin email
  # also matches, which proves this is the account the operator configured. A
  # user who merely grabbed the username is left untouched.
  defp promote_configured_admin(%User{email: email} = user, email, password) do
    grant_admin(user.username, password)
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

  defp validate_optional_password(nil), do: :ok

  defp validate_optional_password(password) when is_binary(password),
    do: validate_password(password)

  defp validate_optional_password(_password), do: {:error, "password must be a string"}

  defp validate_username(username) do
    if Regex.match?(@username_re, username) do
      :ok
    else
      {:error, "username must be 3-32 characters (letters, numbers, _ or -)"}
    end
  end

  defp validate_email(email) do
    if Regex.match?(@email_re, email) and byte_size(email) <= 254 do
      :ok
    else
      {:error, "a valid email address is required"}
    end
  end

  defp validate_password(password) do
    if String.length(password) >= @min_password do
      :ok
    else
      {:error, "password must be at least #{@min_password} characters"}
    end
  end

  defp fetch(attrs, key) when is_map(attrs) do
    Map.get(attrs, to_string(key)) || Map.get(attrs, key) || ""
  end

  defp hash(password), do: Argon2.hash_pwd_salt(to_string(password), hash_opts())

  # Read from app config instead of Mix.env() so releases (where Mix is not
  # available at runtime) don't crash on register/login.
  defp hash_opts do
    Application.get_env(:grange, :argon2_opts, [])
  end

  defp hash_token(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  defp broadcast_players do
    players = list_users() |> Enum.map(&%{name: &1.username})
    GrangeWeb.Endpoint.broadcast(@lobby_topic, "players", %{players: players})
  end
end
