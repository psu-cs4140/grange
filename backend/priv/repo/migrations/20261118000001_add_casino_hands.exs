defmodule Grange.Repo.Migrations.AddCasinoHands do
  use Ecto.Migration

  def change do
    create table(:casino_hands, primary_key: false) do
      add(:user_id, references(:users, type: :string, on_delete: :delete_all), primary_key: true)
      add(:game, :string, primary_key: true)
      add(:version, :integer, default: 0, null: false)
      add(:state, :map, null: false)
    end

    create table(:casino_actions) do
      add(:user_id, references(:users, type: :string, on_delete: :delete_all), null: false)
      add(:game, :string, null: false)
      add(:action_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:request, :map, null: false)
      add(:response, :map)
    end

    create unique_index(:casino_actions, [:user_id, :game, :action_id])
  end
end
