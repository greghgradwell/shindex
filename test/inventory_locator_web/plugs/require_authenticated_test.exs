defmodule InventoryLocatorWeb.Plugs.RequireAuthenticatedTest do
  use InventoryLocatorWeb.ConnCase

  alias InventoryLocator.DataCase
  alias InventoryLocatorWeb.Plugs.RequireAuthenticated

  describe "call/2" do
    test "allows authenticated users through" do
      user = DataCase.create_test_user(%{name: "Auth User", role: "admin"})

      conn =
        Phoenix.ConnTest.build_conn()
        |> init_test_session(%{user_id: user.id})
        |> RequireAuthenticated.call([])

      assert conn.assigns.current_user.id == user.id
      refute conn.halted
    end

    test "allows guests with guest_inventory_id through" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> init_test_session(%{guest_inventory_id: 1})
        |> RequireAuthenticated.call([])

      assert conn.assigns[:guest_session] == true
      refute conn.halted
    end

    test "redirects unauthenticated users without guest session" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAuthenticated.call([])

      assert conn.halted
      assert redirected_to(conn) == "/landing"
    end
  end
end
