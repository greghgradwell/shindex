defmodule InventoryLocatorWeb.InventoryLive.IndexTest do
  use InventoryLocatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias InventoryLocator.Inventory

  describe "Index" do
    test "renders inventory list on mount", %{conn: conn, inventory: inventory} do
      {:ok, _view, html} = live(conn, ~p"/inventories")

      assert html =~ "Inventories"
      assert html =~ inventory.name
      assert html =~ "Current"
    end

    test "shows shelf and item counts", %{conn: conn, inventory: inventory} do
      {:ok, _item} =
        Inventory.create_item_with_location(%{
          inventory_id: inventory.id,
          location_code: "A-1",
          name: "Test Item",
          quantity: 5
        })

      {:ok, _view, html} = live(conn, ~p"/inventories")

      assert html =~ ">1<"
    end

    test "opens create modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/inventories")

      html =
        view
        |> element("button", "New Inventory")
        |> render_click()

      assert html =~ "Create New Inventory"
      assert html =~ "Name"
    end

    test "creates new inventory", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/inventories")

      view
      |> element("button", "New Inventory")
      |> render_click()

      html =
        view
        |> form("form", %{name: "Workshop", description: "My workshop"})
        |> render_submit()

      assert html =~ "Workshop"
      assert html =~ "My workshop"
    end

    test "validates name length", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/inventories")

      view
      |> element("button", "New Inventory")
      |> render_click()

      long_name = String.duplicate("a", 51)

      html =
        view
        |> form("form", %{name: long_name})
        |> render_change()

      assert html =~ "50 characters or less"
    end

    test "validates unique name", %{conn: conn, inventory: inventory} do
      {:ok, view, _html} = live(conn, ~p"/inventories")

      view
      |> element("button", "New Inventory")
      |> render_click()

      html =
        view
        |> form("form", %{name: inventory.name, description: ""})
        |> render_submit()

      assert html =~ "has already been taken"
    end

    test "opens edit modal", %{conn: conn, inventory: inventory} do
      {:ok, view, _html} = live(conn, ~p"/inventories")

      html =
        view
        |> element("button[phx-click='show_edit_modal'][phx-value-id='#{inventory.id}']")
        |> render_click()

      assert html =~ "Edit Inventory"
      assert html =~ inventory.name
    end

    test "updates inventory", %{conn: conn, inventory: inventory} do
      {:ok, view, _html} = live(conn, ~p"/inventories")

      view
      |> element("button[phx-click='show_edit_modal'][phx-value-id='#{inventory.id}']")
      |> render_click()

      html =
        view
        |> form("form", %{name: "Updated Name", description: "New desc"})
        |> render_submit()

      assert html =~ "Updated Name"
      assert html =~ "New desc"
    end

    test "delete button is disabled for current inventory", %{conn: conn, inventory: inventory} do
      {:ok, _view, html} = live(conn, ~p"/inventories")

      assert html =~ ~r/phx-value-id="#{inventory.id}"[^>]*disabled/
    end

    test "opens delete modal for non-current inventory", %{conn: conn} do
      {:ok, other} = Inventory.create_inventory(%{name: "Other"})

      {:ok, view, _html} = live(conn, ~p"/inventories")

      html =
        view
        |> element("button[phx-click='show_delete_modal'][phx-value-id='#{other.id}']")
        |> render_click()

      assert html =~ "Delete Inventory"
      assert html =~ "This action cannot be undone"
      assert html =~ other.name
    end

    test "requires exact name to enable delete button", %{conn: conn} do
      {:ok, other} = Inventory.create_inventory(%{name: "ToDelete"})

      {:ok, view, _html} = live(conn, ~p"/inventories")

      view
      |> element("button[phx-click='show_delete_modal'][phx-value-id='#{other.id}']")
      |> render_click()

      html =
        view
        |> form("form", %{confirmation: "wrong"})
        |> render_change()

      assert html =~ ~r/type="submit"[^>]*disabled/

      html =
        view
        |> form("form", %{confirmation: "ToDelete"})
        |> render_change()

      refute html =~ ~r/type="submit"[^>]*disabled/
    end

    test "deletes inventory with correct confirmation", %{conn: conn} do
      {:ok, other} = Inventory.create_inventory(%{name: "ToDelete"})

      {:ok, view, _html} = live(conn, ~p"/inventories")

      view
      |> element("button[phx-click='show_delete_modal'][phx-value-id='#{other.id}']")
      |> render_click()

      view
      |> form("form", %{confirmation: "ToDelete"})
      |> render_change()

      html =
        view
        |> form("form", %{confirmation: "ToDelete"})
        |> render_submit()

      refute html =~ ">ToDelete<"
    end

    test "prevents deleting last inventory", %{conn: _conn, inventory: inventory} do
      initial_count = Inventory.count_inventories()

      result = Inventory.delete_inventory(inventory)

      if initial_count == 1 do
        assert result == {:error, :last_inventory}
      else
        assert {:ok, _} = result
      end
    end

    test "closes create modal with escape key", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/inventories")

      view
      |> element("button", "New Inventory")
      |> render_click()

      html = render_keydown(view, "close_create_modal", %{"key" => "Escape"})

      refute html =~ "Create New Inventory"
    end
  end
end
