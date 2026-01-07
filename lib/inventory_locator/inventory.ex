defmodule InventoryLocator.Inventory do
  import Ecto.Query, warn: false
  alias InventoryLocator.Repo

  alias InventoryLocator.Inventory.{Shelf, Bin, Cell, Location, ItemType}

  # Shelves

  def list_shelves do
    Repo.all(Shelf)
  end

  def get_shelf!(id), do: Repo.get!(Shelf, id)

  def create_shelf(attrs \\ %{}) do
    %Shelf{}
    |> Shelf.changeset(attrs)
    |> Repo.insert()
  end

  def create_shelf!(attrs) do
    %Shelf{}
    |> Shelf.changeset(attrs)
    |> Repo.insert!()
  end

  def update_shelf(%Shelf{} = shelf, attrs) do
    shelf
    |> Shelf.changeset(attrs)
    |> Repo.update()
  end

  def delete_shelf(%Shelf{} = shelf) do
    Repo.delete(shelf)
  end

  def change_shelf(%Shelf{} = shelf, attrs \\ %{}) do
    Shelf.changeset(shelf, attrs)
  end

  # Bins

  def list_bins do
    Repo.all(Bin)
  end

  def get_bin!(id), do: Repo.get!(Bin, id)

  def create_bin(attrs \\ %{}) do
    %Bin{}
    |> Bin.changeset(attrs)
    |> Repo.insert()
  end

  def create_bin!(attrs) do
    %Bin{}
    |> Bin.changeset(attrs)
    |> Repo.insert!()
  end

  def update_bin(%Bin{} = bin, attrs) do
    bin
    |> Bin.changeset(attrs)
    |> Repo.update()
  end

  def delete_bin(%Bin{} = bin) do
    Repo.delete(bin)
  end

  def change_bin(%Bin{} = bin, attrs \\ %{}) do
    Bin.changeset(bin, attrs)
  end

  # Cells

  def list_cells do
    Repo.all(Cell)
  end

  def get_cell!(id), do: Repo.get!(Cell, id)

  def create_cell(attrs \\ %{}) do
    %Cell{}
    |> Cell.changeset(attrs)
    |> Repo.insert()
  end

  def create_cell!(attrs) do
    %Cell{}
    |> Cell.changeset(attrs)
    |> Repo.insert!()
  end

  def update_cell(%Cell{} = cell, attrs) do
    cell
    |> Cell.changeset(attrs)
    |> Repo.update()
  end

  def delete_cell(%Cell{} = cell) do
    Repo.delete(cell)
  end

  def change_cell(%Cell{} = cell, attrs \\ %{}) do
    Cell.changeset(cell, attrs)
  end

  # Locations

  def list_locations do
    Repo.all(Location)
  end

  def get_location!(id), do: Repo.get!(Location, id)

  def create_location(attrs \\ %{}) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  def create_location!(attrs) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert!()
  end

  def update_location(%Location{} = location, attrs) do
    location
    |> Location.changeset(attrs)
    |> Repo.update()
  end

  def delete_location(%Location{} = location) do
    Repo.delete(location)
  end

  def change_location(%Location{} = location, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  # ItemTypes

  def list_item_types do
    Repo.all(ItemType)
  end

  def get_item_type!(id), do: Repo.get!(ItemType, id)

  def create_item_type(attrs \\ %{}) do
    %ItemType{}
    |> ItemType.changeset(attrs)
    |> Repo.insert()
  end

  def create_item_type!(attrs) do
    %ItemType{}
    |> ItemType.changeset(attrs)
    |> Repo.insert!()
  end

  def update_item_type(%ItemType{} = item_type, attrs) do
    item_type
    |> ItemType.changeset(attrs)
    |> Repo.update()
  end

  def delete_item_type(%ItemType{} = item_type) do
    Repo.delete(item_type)
  end

  def change_item_type(%ItemType{} = item_type, attrs \\ %{}) do
    ItemType.changeset(item_type, attrs)
  end
end
