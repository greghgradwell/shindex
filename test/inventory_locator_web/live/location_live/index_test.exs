defmodule InventoryLocatorWeb.LocationLive.IndexTest do
  use InventoryLocatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias InventoryLocator.Inventory
  alias InventoryLocator.Repo

  describe "Index" do
    test "lists all shelves with hierarchy", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "Test Item", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "A"
      assert html =~ "Location Management"
    end

    test "shows shelf code", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "Test", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "A"
    end

    test "shows bin code in hierarchy", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-3-1", "Test", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "Bin 3"
    end

    test "shows cell code", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-2", "Test", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "2"
    end

    test "deletes empty location on click", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 1, "Test")
      item = Repo.preload(item, :location)
      Inventory.delete_item_type(item)

      {:ok, index_live, _html} = live(conn, ~p"/locations")

      index_live
      |> element("button.btn-ghost")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Inventory.get_location!(item.location.id) end
    end

    test "prevents deletion of occupied location", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 1, "Test")
      item = Repo.preload(item, :location)

      {:ok, _index_live, html} = live(conn, ~p"/locations")

      refute html =~ "hero-trash"
      assert Inventory.get_location!(item.location.id)
    end

    test "updates view after deleting location", %{conn: conn} do
      {:ok, item1} = Inventory.create_item_with_location("A-1-1", "Item 1", 1, "Test")
      {:ok, item2} = Inventory.create_item_with_location("A-2-1", "Item 2", 1, "Test")
      item1 = Repo.preload(item1, :location)
      item2 = Repo.preload(item2, :location)
      Inventory.delete_item_type(item1)
      Inventory.delete_item_type(item2)

      {:ok, index_live, _html} = live(conn, ~p"/locations")

      index_live
      |> element("button[phx-click*='delete_location'][phx-click*='#{item2.location.id}']")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Inventory.get_location!(item2.location.id) end
    end

    test "shows occupied indicator for locations with items", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "Test Item", 5, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "Test Item"
    end

    test "shows delete button for empty locations", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 1, "Test")
      Inventory.delete_item_type(item)

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "hero-trash"
      assert html =~ "data-confirm=\"Delete this empty location?\""
    end

    test "multiple shelves displayed correctly", %{conn: conn} do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-1", "Item 1", 1, "Test")
      {:ok, _item2} = Inventory.create_item_with_location("B-1-1", "Item 2", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "A"
      assert html =~ "B"
    end

    test "shows multiple items as clickable buttons in same cell", %{conn: conn} do
      {:ok, item1} = Inventory.create_item_with_location("A-1-1", "Item 1", 5, "Desc")
      {:ok, item2} = Inventory.create_item_with_location("A-1-1", "Item 2", 3, "Desc")

      {:ok, _index_live, html} = live(conn, ~p"/locations")

      assert html =~ "Item 1"
      assert html =~ "Item 2"
      assert html =~ "phx-value-id=\"#{item1.id}\""
      assert html =~ "phx-value-id=\"#{item2.id}\""
    end

    test "clicking item opens detail modal", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test Item", 5, "Test Description")

      {:ok, view, _html} = live(conn, ~p"/locations")

      html =
        view
        |> element("button[phx-value-id='#{item.id}']")
        |> render_click()

      assert html =~ "modal modal-open"
      assert html =~ "Test Item"
      assert html =~ "A-1-1"
    end
  end
end
