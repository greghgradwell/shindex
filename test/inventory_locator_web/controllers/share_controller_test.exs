defmodule InventoryLocatorWeb.ShareControllerTest do
  use InventoryLocatorWeb.ConnCase

  alias InventoryLocator.DataCase
  alias InventoryLocator.Inventory

  setup do
    owner = DataCase.create_test_user(%{name: "Owner", role: "admin"})
    inventory = DataCase.create_test_inventory(%{user_id: owner.id})
    {:ok, link} = Inventory.create_public_link(inventory.id, owner.id)
    %{owner: owner, inventory: inventory, link: link}
  end

  describe "GET /view/:code (enter_guest)" do
    test "valid public link sets guest session and redirects", %{conn: conn, link: link, inventory: inventory} do
      conn = get(conn, ~p"/view/#{link.code}")
      assert redirected_to(conn) == "/"
      assert get_session(conn, :guest_inventory_id) == inventory.id
    end

    test "invalid code redirects to landing with error", %{conn: conn} do
      conn = get(conn, ~p"/view/BADCODE")
      assert redirected_to(conn) == "/landing"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end
  end
end
