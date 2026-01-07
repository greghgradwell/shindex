defmodule InventoryLocator.Inventory do
  import Ecto.Query, warn: false
  alias InventoryLocator.Repo

  alias InventoryLocator.Inventory.{Shelf, Bin, Cell, Location, ItemType}

  # Shelves

  @spec list_shelves() :: [Shelf.t()]
  def list_shelves do
    Repo.all(Shelf)
  end

  @spec get_shelf!(integer()) :: Shelf.t()
  def get_shelf!(id), do: Repo.get!(Shelf, id)

  @spec create_shelf(map()) :: {:ok, Shelf.t()} | {:error, Ecto.Changeset.t()}
  def create_shelf(attrs \\ %{}) do
    %Shelf{}
    |> Shelf.changeset(attrs)
    |> Repo.insert()
  end

  @spec create_shelf!(map()) :: Shelf.t()
  def create_shelf!(attrs) do
    %Shelf{}
    |> Shelf.changeset(attrs)
    |> Repo.insert!()
  end

  @spec update_shelf(Shelf.t(), map()) :: {:ok, Shelf.t()} | {:error, Ecto.Changeset.t()}
  def update_shelf(%Shelf{} = shelf, attrs) do
    shelf
    |> Shelf.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_shelf(Shelf.t()) :: {:ok, Shelf.t()} | {:error, Ecto.Changeset.t()}
  def delete_shelf(%Shelf{} = shelf) do
    Repo.delete(shelf)
  end

  @spec change_shelf(Shelf.t(), map()) :: Ecto.Changeset.t()
  def change_shelf(%Shelf{} = shelf, attrs \\ %{}) do
    Shelf.changeset(shelf, attrs)
  end

  # Bins

  @spec list_bins() :: [Bin.t()]
  def list_bins do
    Repo.all(Bin)
  end

  @spec get_bin!(integer()) :: Bin.t()
  def get_bin!(id), do: Repo.get!(Bin, id)

  @spec create_bin(map()) :: {:ok, Bin.t()} | {:error, Ecto.Changeset.t()}
  def create_bin(attrs \\ %{}) do
    %Bin{}
    |> Bin.changeset(attrs)
    |> Repo.insert()
  end

  @spec create_bin!(map()) :: Bin.t()
  def create_bin!(attrs) do
    %Bin{}
    |> Bin.changeset(attrs)
    |> Repo.insert!()
  end

  @spec update_bin(Bin.t(), map()) :: {:ok, Bin.t()} | {:error, Ecto.Changeset.t()}
  def update_bin(%Bin{} = bin, attrs) do
    bin
    |> Bin.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_bin(Bin.t()) :: {:ok, Bin.t()} | {:error, Ecto.Changeset.t()}
  def delete_bin(%Bin{} = bin) do
    Repo.delete(bin)
  end

  @spec change_bin(Bin.t(), map()) :: Ecto.Changeset.t()
  def change_bin(%Bin{} = bin, attrs \\ %{}) do
    Bin.changeset(bin, attrs)
  end

  # Cells

  @spec list_cells() :: [Cell.t()]
  def list_cells do
    Repo.all(Cell)
  end

  @spec get_cell!(integer()) :: Cell.t()
  def get_cell!(id), do: Repo.get!(Cell, id)

  @spec create_cell(map()) :: {:ok, Cell.t()} | {:error, Ecto.Changeset.t()}
  def create_cell(attrs \\ %{}) do
    %Cell{}
    |> Cell.changeset(attrs)
    |> Repo.insert()
  end

  @spec create_cell!(map()) :: Cell.t()
  def create_cell!(attrs) do
    %Cell{}
    |> Cell.changeset(attrs)
    |> Repo.insert!()
  end

  @spec update_cell(Cell.t(), map()) :: {:ok, Cell.t()} | {:error, Ecto.Changeset.t()}
  def update_cell(%Cell{} = cell, attrs) do
    cell
    |> Cell.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_cell(Cell.t()) :: {:ok, Cell.t()} | {:error, Ecto.Changeset.t()}
  def delete_cell(%Cell{} = cell) do
    Repo.delete(cell)
  end

  @spec change_cell(Cell.t(), map()) :: Ecto.Changeset.t()
  def change_cell(%Cell{} = cell, attrs \\ %{}) do
    Cell.changeset(cell, attrs)
  end

  # Locations

  @spec list_locations() :: [Location.t()]
  def list_locations do
    Repo.all(Location)
  end

  @spec get_location!(integer()) :: Location.t()
  def get_location!(id), do: Repo.get!(Location, id)

  @spec create_location(map()) :: {:ok, Location.t()} | {:error, Ecto.Changeset.t()}
  def create_location(attrs \\ %{}) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  @spec create_location!(map()) :: Location.t()
  def create_location!(attrs) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert!()
  end

  @spec update_location(Location.t(), map()) :: {:ok, Location.t()} | {:error, Ecto.Changeset.t()}
  def update_location(%Location{} = location, attrs) do
    location
    |> Location.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_location(Location.t()) :: {:ok, Location.t()} | {:error, Ecto.Changeset.t()}
  def delete_location(%Location{} = location) do
    Repo.delete(location)
  end

  @spec change_location(Location.t(), map()) :: Ecto.Changeset.t()
  def change_location(%Location{} = location, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  # ItemTypes

  @spec list_item_types() :: [ItemType.t()]
  def list_item_types do
    Repo.all(ItemType)
  end

  @spec get_item_type!(integer()) :: ItemType.t()
  def get_item_type!(id), do: Repo.get!(ItemType, id)

  @spec create_item_type(map()) :: {:ok, ItemType.t()} | {:error, Ecto.Changeset.t()}
  def create_item_type(attrs \\ %{}) do
    %ItemType{}
    |> ItemType.changeset(attrs)
    |> Repo.insert()
  end

  @spec create_item_type!(map()) :: ItemType.t()
  def create_item_type!(attrs) do
    %ItemType{}
    |> ItemType.changeset(attrs)
    |> Repo.insert!()
  end

  @spec update_item_type(ItemType.t(), map()) ::
          {:ok, ItemType.t()} | {:error, Ecto.Changeset.t()}
  def update_item_type(%ItemType{} = item_type, attrs) do
    item_type
    |> ItemType.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_item_type(ItemType.t()) :: {:ok, ItemType.t()} | {:error, Ecto.Changeset.t()}
  def delete_item_type(%ItemType{} = item_type) do
    Repo.delete(item_type)
  end

  @spec change_item_type(ItemType.t(), map()) :: Ecto.Changeset.t()
  def change_item_type(%ItemType{} = item_type, attrs \\ %{}) do
    ItemType.changeset(item_type, attrs)
  end
end
