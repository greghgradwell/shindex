defmodule InventoryLocatorWeb.LocationLive.IndexTest do
  use InventoryLocatorWeb.ConnCase

  import Phoenix.LiveViewTest
  alias InventoryLocator.{Inventory, Repo}

  describe "Index" do
    test "lists all shelves with hierarchy", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Test Item", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "A"
      assert html =~ "Location Management"
    end

    test "displays occupancy stats for occupied locations", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Test Item", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "1 occupied"
      assert html =~ "0 empty"
    end

    test "displays occupancy stats for empty locations", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-0", "Test", 1, "Test")
      Inventory.delete_item_type(item)

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "0 occupied"
      assert html =~ "1 empty"
    end

    test "shows shelf code", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Test", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "A"
    end

    test "shows bin code in hierarchy", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-3-0", "Test", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "Bin 3"
    end

    test "shows cell code", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-2", "Test", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "2"
    end

    test "deletes empty location on click", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-0", "Test", 1, "Test")
      item = Repo.preload(item, :location)
      Inventory.delete_item_type(item)

      {:ok, index_live, html} = live(conn, ~p"/locations")
      assert html =~ "1 empty"

      html =
        index_live
        |> element("button.btn-ghost")
        |> render_click()

      assert html =~ "0 empty"
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_location!(item.location.id) end
    end

    test "prevents deletion of occupied location", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-0", "Test", 1, "Test")
      item = Repo.preload(item, :location)

      {:ok, _index_live, html} = live(conn, ~p"/locations")

      refute html =~ "hero-trash"
      assert Inventory.get_location!(item.location.id)
    end

    test "updates stats after deleting location", %{conn: conn} do
      {:ok, item1} = Inventory.create_item_with_location("A-1-0", "Item 1", 1, "Test")
      {:ok, item2} = Inventory.create_item_with_location("A-2-0", "Item 2", 1, "Test")
      item1 = Repo.preload(item1, :location)
      item2 = Repo.preload(item2, :location)
      Inventory.delete_item_type(item1)
      Inventory.delete_item_type(item2)

      {:ok, index_live, html} = live(conn, ~p"/locations")
      assert html =~ "2 empty"

      index_live
      |> element("button[phx-click*='delete_location'][phx-click*='#{item2.location.id}']")
      |> render_click()

      html = render(index_live)
      assert html =~ "1 empty"
    end

    test "shows occupied indicator for locations with items", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-0", "Test", 5, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "hero-check-circle-solid"
    end

    test "shows delete button for empty locations", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-0", "Test", 1, "Test")
      Inventory.delete_item_type(item)

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "hero-trash"
      assert html =~ "data-confirm=\"Delete this empty location?\""
    end

    test "multiple shelves displayed correctly", %{conn: conn} do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-0", "Item 1", 1, "Test")
      {:ok, _item2} = Inventory.create_item_with_location("B-1-0", "Item 2", 1, "Test")

      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "A"
      assert html =~ "B"
    end

    test "empty shelves list shows no locations", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/locations")
      assert html =~ "0 empty"
      assert html =~ "0 occupied"
    end
  end
end
