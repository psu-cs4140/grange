defmodule Grange.Repo.Migrations.AddSlotSpins do
  use Ecto.Migration

  def change do
    create table(:slot_spins) do
      add(:user_id, references(:users, type: :string, on_delete: :delete_all), null: false)
      add(:spin_id, :string, null: false)
      add(:bet, :integer, null: false)
      add(:result, :map)
    end

    create unique_index(:slot_spins, [:user_id, :spin_id])
  end
end
