defmodule Grange.Repo.Migrations.AddFarmAnimals do
  use Ecto.Migration

  def change do
    alter table(:farms) do
      add(:animals, :map, null: false, default: %{})
    end
  end
end
