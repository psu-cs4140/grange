defmodule Grange.CasinoHands do
  @moduledoc "Persists private card-game state and commits each accepted action once."

  import Ecto.Query
  alias Grange.{Repo, User}

  @games ~w(blackjack poker)

  @doc "Returns the current version and a game-defined public projection."
  def resume(user_id, game, project) when game in @games and is_function(project, 1) do
    version_and_state =
      Repo.one(
        from(h in "casino_hands",
          where: h.user_id == ^user_id and h.game == ^game,
          select: {h.version, type(h.state, :map)}
        )
      )

    {version, state} = version_and_state || {0, %{}}
    %{"version" => version, "hand" => project.(state)}
  end

  @doc """
  Runs a trusted game transition with the saved private state and current wallet.
  The transition supplies the next private state, public projection, and wallet
  balance. The request is used for replay comparison, not as a wallet update.
  """
  def act(user_id, game, action_id, version, request, transition)
      when game in @games and is_binary(action_id) and is_integer(version) and version >= 0 and
             is_map(request) and is_function(transition, 2) do
    case Ecto.UUID.cast(action_id) do
      {:ok, id} ->
        Repo.transaction(fn ->
          apply_action(user_id, game, id, version, request, transition)
        end)

      :error ->
        {:error, :invalid_action}
    end
  end

  def act(_, _, _, _, _, _), do: {:error, :invalid_action}

  defp apply_action(user_id, game, id, version, request, transition) do
    # Claim the action first so concurrent SQLite writers cannot read an old
    # wallet or hand version while another action is being committed.
    row = %{
      user_id: user_id,
      game: game,
      action_id: id,
      version: version,
      request: Jason.encode!(request)
    }

    {count, _} =
      Repo.insert_all("casino_actions", [row],
        on_conflict: :nothing,
        conflict_target: [:user_id, :game, :action_id]
      )

    action =
      from(a in "casino_actions",
        where: a.user_id == ^user_id and a.game == ^game and a.action_id == ^id
      )

    if count == 0 do
      replay(action, version, request)
    else
      commit(action, user_id, game, version, transition)
    end
  end

  defp replay(action, version, request) do
    stored =
      Repo.one!(select(action, [a], {a.version, type(a.request, :map), type(a.response, :map)}))

    case stored do
      {^version, ^request, response} -> response
      _ -> Repo.rollback(:action_conflict)
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp commit(action, user_id, game, version, transition) do
    hand = from(h in "casino_hands", where: h.user_id == ^user_id and h.game == ^game)
    current = Repo.one(select(hand, [h], {h.version, type(h.state, :map)}))
    {current_version, state} = current || {0, %{}}
    if current_version != version, do: Repo.rollback(:stale_hand)

    user = Repo.get!(User, user_id)

    case transition.(state, user.balance) do
      {:ok, next_state, public_state, balance}
      when is_map(next_state) and is_map(public_state) and is_integer(balance) and balance >= 0 ->
        next_version = version + 1
        save_hand(user_id, game, next_version, next_state)
        Repo.update!(Ecto.Changeset.change(user, balance: balance))
        response = %{"hand" => public_state, "version" => next_version, "balance" => balance}

        Repo.update_all(
          from(a in action, update: [set: [response: type(^response, :map)]]),
          []
        )

        response

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp save_hand(user_id, game, version, state) do
    row = %{user_id: user_id, game: game, version: version, state: Jason.encode!(state)}

    Repo.insert_all("casino_hands", [row],
      on_conflict: {:replace, [:version, :state]},
      conflict_target: [:user_id, :game]
    )
  end
end
