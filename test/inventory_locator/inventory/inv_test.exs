defmodule InventoryLocator.Inventory.InvTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.Inv

  setup do
    Repo.delete_all(Inv)
    :ok
  end

  describe "create_inventory/1" do
    test "creates inventory with valid attributes" do
      attrs = %{name: "Workshop", description: "Main workshop inventory"}

      assert {:ok, inventory} = Inventory.create_inventory(attrs)
      assert inventory.name == "Workshop"
      assert inventory.description == "Main workshop inventory"
    end

    test "creates inventory without description" do
      attrs = %{name: "Kitchen"}

      assert {:ok, inventory} = Inventory.create_inventory(attrs)
      assert inventory.name == "Kitchen"
      assert inventory.description == nil
    end

    test "returns error for missing name" do
      attrs = %{description: "No name"}

      assert {:error, changeset} = Inventory.create_inventory(attrs)
      assert changeset.errors[:name]
    end

    test "enforces unique name constraint" do
      attrs = %{name: "Unique"}

      {:ok, _first} = Inventory.create_inventory(attrs)
      assert {:error, changeset} = Inventory.create_inventory(attrs)
      assert changeset.errors[:name]
    end
  end

  describe "list_inventories/0" do
    test "returns empty list when no inventories exist" do
      assert Inventory.list_inventories() == []
    end

    test "returns all inventories ordered by name" do
      {:ok, _inv1} = Inventory.create_inventory(%{name: "Zebra"})
      {:ok, _inv2} = Inventory.create_inventory(%{name: "Alpha"})
      {:ok, _inv3} = Inventory.create_inventory(%{name: "Beta"})

      inventories = Inventory.list_inventories()
      names = Enum.map(inventories, & &1.name)

      assert names == ["Alpha", "Beta", "Zebra"]
    end
  end

  describe "get_inventory!/1" do
    test "returns inventory by id" do
      {:ok, created} = Inventory.create_inventory(%{name: "Test"})

      fetched = Inventory.get_inventory!(created.id)
      assert fetched.id == created.id
      assert fetched.name == "Test"
    end

    test "raises when inventory not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Inventory.get_inventory!(999_999)
      end
    end
  end

  describe "get_inventory_by_name/1" do
    test "returns inventory by name" do
      {:ok, created} = Inventory.create_inventory(%{name: "FindMe"})

      fetched = Inventory.get_inventory_by_name("FindMe")
      assert fetched.id == created.id
    end

    test "returns nil when not found" do
      assert Inventory.get_inventory_by_name("NotFound") == nil
    end
  end

  describe "get_first_inventory!/0" do
    test "returns first inventory by name" do
      {:ok, _inv1} = Inventory.create_inventory(%{name: "Zebra"})
      {:ok, inv2} = Inventory.create_inventory(%{name: "Alpha"})

      first = Inventory.get_first_inventory!()
      assert first.id == inv2.id
    end

    test "raises when no inventories exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Inventory.get_first_inventory!()
      end
    end
  end

  describe "update_inventory/2" do
    test "updates inventory attributes" do
      {:ok, inventory} = Inventory.create_inventory(%{name: "Old"})

      {:ok, updated} = Inventory.update_inventory(inventory, %{name: "New", description: "Updated"})
      assert updated.name == "New"
      assert updated.description == "Updated"
    end

    test "returns error for invalid update" do
      {:ok, inventory} = Inventory.create_inventory(%{name: "Valid"})

      assert {:error, changeset} = Inventory.update_inventory(inventory, %{name: ""})
      assert changeset.errors[:name]
    end
  end

  describe "inventory associations" do
    test "shelves are associated with inventory" do
      {:ok, inventory} = Inventory.create_inventory(%{name: "Test"})
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "A"}, 1)

      inventory = Repo.preload(inventory, :shelves)
      assert length(inventory.shelves) == 1
      assert hd(inventory.shelves).id == shelf.id
    end

    test "item_types are associated with inventory" do
      {:ok, inventory} = Inventory.create_inventory(%{name: "Test"})
      {:ok, item} = Inventory.create_item_with_location(inventory.id, "A-1-1", "Test Item", 1, "Desc")

      inventory = Repo.preload(inventory, :item_types)
      assert length(inventory.item_types) == 1
      assert hd(inventory.item_types).id == item.id
    end
  end
end
