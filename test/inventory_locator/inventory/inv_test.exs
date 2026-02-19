defmodule InventoryLocator.Inventory.InvTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.Inv

  setup do
    Repo.delete_all(Inv)
    user = create_test_user(%{name: "Test Owner", role: "admin"})
    {:ok, user: user}
  end

  describe "create_inventory/1" do
    test "creates inventory with valid attributes", %{user: user} do
      attrs = %{name: "Workshop", description: "Main workshop inventory", user_id: user.id}

      assert {:ok, inventory} = Inventory.create_inventory(attrs)
      assert inventory.name == "Workshop"
      assert inventory.description == "Main workshop inventory"
      assert inventory.user_id == user.id
    end

    test "creates inventory without description", %{user: user} do
      attrs = %{name: "Kitchen", user_id: user.id}

      assert {:ok, inventory} = Inventory.create_inventory(attrs)
      assert inventory.name == "Kitchen"
      assert inventory.description == nil
    end

    test "returns error for missing name", %{user: user} do
      attrs = %{description: "No name", user_id: user.id}

      assert {:error, changeset} = Inventory.create_inventory(attrs)
      assert changeset.errors[:name]
    end

    test "returns error for missing user_id" do
      attrs = %{name: "No owner"}

      assert {:error, changeset} = Inventory.create_inventory(attrs)
      assert changeset.errors[:user_id]
    end

    test "enforces unique name per user constraint", %{user: user} do
      attrs = %{name: "Unique", user_id: user.id}

      {:ok, _first} = Inventory.create_inventory(attrs)
      assert {:error, changeset} = Inventory.create_inventory(attrs)
      assert changeset.errors[:name]
    end

    test "allows same name for different users", %{user: user} do
      other_user = create_test_user(%{name: "Other User", role: "member"})

      {:ok, _first} = Inventory.create_inventory(%{name: "Workshop", user_id: user.id})
      assert {:ok, _second} = Inventory.create_inventory(%{name: "Workshop", user_id: other_user.id})
    end
  end

  describe "list_accessible_inventories/1" do
    test "returns empty list when no inventories exist", %{user: user} do
      assert Inventory.list_accessible_inventories(user.id) == []
    end

    test "returns only user's inventories ordered by name", %{user: user} do
      other_user = create_test_user(%{name: "Other", role: "member"})

      {:ok, _inv1} = Inventory.create_inventory(%{name: "Zebra", user_id: user.id})
      {:ok, _inv2} = Inventory.create_inventory(%{name: "Alpha", user_id: user.id})
      {:ok, _inv3} = Inventory.create_inventory(%{name: "Other's Inv", user_id: other_user.id})

      inventories = Inventory.list_accessible_inventories(user.id)
      names = Enum.map(inventories, & &1.name)

      assert names == ["Alpha", "Zebra"]
    end
  end

  describe "get_inventory!/1" do
    test "returns inventory by id", %{user: user} do
      {:ok, created} = Inventory.create_inventory(%{name: "Test", user_id: user.id})

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

  describe "get_first_inventory!/1" do
    test "returns first inventory by name for user", %{user: user} do
      {:ok, _inv1} = Inventory.create_inventory(%{name: "Zebra", user_id: user.id})
      {:ok, inv2} = Inventory.create_inventory(%{name: "Alpha", user_id: user.id})

      first = Inventory.get_first_inventory!(user.id)
      assert first.id == inv2.id
    end

    test "raises when no inventories exist for user", %{user: user} do
      assert_raise Ecto.NoResultsError, fn ->
        Inventory.get_first_inventory!(user.id)
      end
    end
  end

  describe "update_inventory/2" do
    test "updates inventory attributes", %{user: user} do
      {:ok, inventory} = Inventory.create_inventory(%{name: "Old", user_id: user.id})

      {:ok, updated} = Inventory.update_inventory(inventory, %{name: "New", description: "Updated"})
      assert updated.name == "New"
      assert updated.description == "Updated"
    end

    test "returns error for invalid update", %{user: user} do
      {:ok, inventory} = Inventory.create_inventory(%{name: "Valid", user_id: user.id})

      assert {:error, changeset} = Inventory.update_inventory(inventory, %{name: ""})
      assert changeset.errors[:name]
    end
  end

  describe "user_can_access?/2" do
    test "returns true for owned inventory", %{user: user} do
      {:ok, inv} = Inventory.create_inventory(%{name: "Mine", user_id: user.id})

      assert Inventory.user_can_access?(user.id, inv.id)
    end

    test "returns false for other user's inventory", %{user: user} do
      other_user = create_test_user(%{name: "Other", role: "member"})
      {:ok, inv} = Inventory.create_inventory(%{name: "Theirs", user_id: other_user.id})

      refute Inventory.user_can_access?(user.id, inv.id)
    end
  end

  describe "inventory associations" do
    test "shelves are associated with inventory", %{user: user} do
      {:ok, inventory} = Inventory.create_inventory(%{name: "Test", user_id: user.id})
      {:ok, shelf} = Inventory.create_shelf_with_bins(inventory.id, %{code: "A"}, 1)

      inventory = Repo.preload(inventory, :shelves)
      assert length(inventory.shelves) == 1
      assert hd(inventory.shelves).id == shelf.id
    end

    test "item_types are associated with inventory", %{user: user} do
      {:ok, inventory} = Inventory.create_inventory(%{name: "Test", user_id: user.id})

      {:ok, item} =
        Inventory.create_item_with_location(%{
          inventory_id: inventory.id,
          location_code: "A-1",
          name: "Test Item"
        })

      inventory = Repo.preload(inventory, :item_types)
      assert length(inventory.item_types) == 1
      assert hd(inventory.item_types).id == item.id
    end
  end
end
