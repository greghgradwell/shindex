defmodule InventoryLocator.Repo.Migrations.AllowZeroQuantity do
  use Ecto.Migration

  def change do
    create constraint(:item_types, :quantity_non_negative, check: "quantity >= 0")
  end
end
