defmodule InventoryLocator.Inventory.PublicLinkTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory
  alias InventoryLocator.Inventory.InventoryShareCode

  setup do
    owner = create_test_user(%{name: "Owner", role: "admin"})
    viewer = create_test_user(%{name: "Viewer", role: "member"})
    inventory = create_test_inventory(%{user_id: owner.id})
    %{owner: owner, viewer: viewer, inventory: inventory}
  end

  describe "create_public_link/2" do
    test "creates a reusable share code", %{inventory: inventory, owner: owner} do
      assert {:ok, link} = Inventory.create_public_link(inventory.id, owner.id)
      assert link.reusable == true
      assert link.role == "viewer"
      assert link.inventory_id == inventory.id
    end

    test "returns existing link instead of creating duplicate", %{inventory: inventory, owner: owner} do
      assert {:ok, first} = Inventory.create_public_link(inventory.id, owner.id)
      assert {:ok, second} = Inventory.create_public_link(inventory.id, owner.id)
      assert first.id == second.id
    end
  end

  describe "get_public_link/1" do
    test "returns nil when no public link exists", %{inventory: inventory} do
      assert Inventory.get_public_link(inventory.id) == nil
    end

    test "returns the active public link", %{inventory: inventory, owner: owner} do
      {:ok, link} = Inventory.create_public_link(inventory.id, owner.id)
      assert Inventory.get_public_link(inventory.id).id == link.id
    end
  end

  describe "resolve_public_code/1" do
    test "resolves a valid public link to its inventory", %{inventory: inventory, owner: owner} do
      {:ok, link} = Inventory.create_public_link(inventory.id, owner.id)
      assert {:ok, resolved} = Inventory.resolve_public_code(link.code)
      assert resolved.id == inventory.id
    end

    test "returns :invalid for non-existent code" do
      assert :invalid = Inventory.resolve_public_code("NONEXIST")
    end

    test "returns :invalid for a non-reusable share code", %{inventory: inventory, owner: owner} do
      {:ok, invite} = Inventory.create_share_code(inventory.id, owner.id)
      assert :invalid = Inventory.resolve_public_code(invite.code)
    end

    test "returns :invalid for an expired public link", %{inventory: inventory, owner: owner} do
      {:ok, link} = Inventory.create_public_link(inventory.id, owner.id)

      # Expire the link manually
      link
      |> InventoryShareCode.changeset(%{expires_at: ~U[2020-01-01 00:00:00Z]})
      |> Repo.update!()

      assert :invalid = Inventory.resolve_public_code(link.code)
    end
  end

  describe "revoke_public_link/1" do
    test "deletes a public link", %{inventory: inventory, owner: owner} do
      {:ok, link} = Inventory.create_public_link(inventory.id, owner.id)
      assert {:ok, _} = Inventory.revoke_public_link(link.id)
      assert Inventory.get_public_link(inventory.id) == nil
    end

    test "returns error for non-existent id" do
      assert {:error, :not_found} = Inventory.revoke_public_link(-1)
    end

    test "does not delete a non-reusable share code", %{inventory: inventory, owner: owner} do
      {:ok, invite} = Inventory.create_share_code(inventory.id, owner.id)
      assert {:error, :not_found} = Inventory.revoke_public_link(invite.id)
    end
  end

  describe "public links cannot be redeemed as invite codes" do
    test "redeem_share_code rejects a reusable public link", %{inventory: inventory, owner: owner, viewer: viewer} do
      {:ok, link} = Inventory.create_public_link(inventory.id, owner.id)
      assert {:error, :invalid_code} = Inventory.redeem_share_code(link.code, viewer.id)
    end

    test "get_share_code_info returns nil for a public link", %{inventory: inventory, owner: owner} do
      {:ok, link} = Inventory.create_public_link(inventory.id, owner.id)
      assert Inventory.get_share_code_info(link.code) == nil
    end
  end
end
