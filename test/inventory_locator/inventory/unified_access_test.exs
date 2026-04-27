defmodule InventoryLocator.Inventory.UnifiedAccessTest do
  use InventoryLocator.DataCase

  alias InventoryLocator.Inventory

  setup do
    owner = create_test_user(%{name: "Owner", role: "admin"})
    member_user = create_test_user(%{name: "Member", role: "member"})
    inventory = create_test_inventory(%{user_id: owner.id})
    %{owner: owner, member_user: member_user, inventory: inventory}
  end

  describe "user_role_for_inventory/2" do
    test "returns :owner for inventory owner", %{owner: owner, inventory: inventory} do
      assert Inventory.user_role_for_inventory(owner.id, inventory.id) == :owner
    end

    test "returns :member for shared member", %{member_user: member_user, inventory: inventory, owner: owner} do
      {:ok, _code} = Inventory.create_share_code(inventory.id, owner.id)
      codes = Inventory.list_share_codes(inventory.id)
      code = hd(codes)
      {:ok, _member} = Inventory.redeem_share_code(code.code, member_user.id)
      assert Inventory.user_role_for_inventory(member_user.id, inventory.id) == :member
    end

    test "returns :none for unrelated user", %{inventory: inventory} do
      stranger = create_test_user(%{name: "Stranger", role: "member"})
      assert Inventory.user_role_for_inventory(stranger.id, inventory.id) == :none
    end
  end
end
