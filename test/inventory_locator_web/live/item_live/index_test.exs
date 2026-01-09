defmodule InventoryLocatorWeb.ItemLive.IndexTest do
  use InventoryLocatorWeb.ConnCase

  import Phoenix.LiveViewTest
  alias InventoryLocator.{Inventory, Repo}

  describe "Index" do
    test "renders search box on mount", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/")
      assert html =~ "Search Items"
      assert html =~ "placeholder=\"Search by name...\""
    end

    test "shows empty state message initially", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "Test", 1, "Desc")

      {:ok, _index_live, html} = live(conn, ~p"/")
      assert html =~ "Start typing to search for items or select filters"
    end

    test "searches items on input", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "M3 Screws", 10, "Desc")

      {:ok, index_live, _html} = live(conn, ~p"/")

      html =
        index_live
        |> form("form", %{query: "screw"})
        |> render_change()

      assert html =~ "M3 Screws"
      assert html =~ "1 results"
    end

    test "displays item details in search results", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "M3 Screws", 10, "Test desc")

      {:ok, index_live, _html} = live(conn, ~p"/")

      html =
        index_live
        |> form("form", %{query: "screw"})
        |> render_change()

      assert html =~ "M3 Screws"
      assert html =~ "A-1-1"
      assert html =~ "10 in stock"
    end

    test "handles typos with fuzzy search", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "Screws", 5, "Desc")

      {:ok, index_live, _html} = live(conn, ~p"/")

      html =
        index_live
        |> form("form", %{query: "scres"})
        |> render_change()

      assert html =~ "Screws"
    end

    test "shows placeholder icon for items without photos", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "Test Item", 1, "Desc")

      {:ok, index_live, _html} = live(conn, ~p"/")

      html =
        index_live
        |> form("form", %{query: "test"})
        |> render_change()

      assert html =~ "hero-photo"
    end

    test "toggles archived items visibility", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "Active Item", 10, "Desc")

      {:ok, index_live, html} = live(conn, ~p"/")

      refute html =~ "checked"

      html =
        index_live
        |> element("input[type='checkbox'][phx-click='toggle_archived']")
        |> render_click()

      assert html =~ "checked"
    end

    test "filters by missing manufacturer", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "Item 1", 10, "Desc")

      {:ok, index_live, _html} = live(conn, ~p"/")

      html =
        index_live
        |> element("input[phx-value-filter='manufacturer']")
        |> render_click()

      assert html =~ "Item 1"
      assert html =~ "1 results"
    end

    test "filters by missing model", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "Item 1", 10, "Desc")

      {:ok, index_live, _html} = live(conn, ~p"/")

      html =
        index_live
        |> element("input[phx-value-filter='model']")
        |> render_click()

      assert html =~ "Item 1"
    end

    test "filters by missing description", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Item 1", 10, "Desc")
      item = Repo.preload(item, :location)
      Inventory.delete_item_type(item)

      {:ok, _item2} =
        Inventory.create_item_with_location(item.location.full_code, "Item 2", 5, nil)

      {:ok, index_live, _html} = live(conn, ~p"/")

      html =
        index_live
        |> element("input[phx-value-filter='description']")
        |> render_click()

      assert html =~ "Item 2"
      assert html =~ "1 results"
    end

    test "multiple filters can be active simultaneously", %{conn: conn} do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-1", "Item 1", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location("B-1-1", "Item 2", 20, "Desc")

      {:ok, index_live, _html} = live(conn, ~p"/")

      html =
        index_live
        |> element("input[phx-value-filter='manufacturer']")
        |> render_click()

      assert html =~ "2 results"

      html =
        index_live
        |> element("input[phx-value-filter='model']")
        |> render_click()

      assert html =~ "2 results"
    end

    test "combines search with filters", %{conn: conn} do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-1", "Screws", 10, "Desc")
      {:ok, _item2} = Inventory.create_item_with_location("B-1-1", "Nails", 20, "Desc")

      {:ok, index_live, _html} = live(conn, ~p"/")

      index_live
      |> element("input[phx-value-filter='manufacturer']")
      |> render_click()

      html =
        index_live
        |> form("form", %{query: "screw"})
        |> render_change()

      assert html =~ "Screws"
      assert html =~ "1 results"
      refute html =~ "Nails"
    end

    test "unchecking filter removes it", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("A-1-1", "Item 1", 10, "Desc")

      {:ok, index_live, _html} = live(conn, ~p"/")

      html =
        index_live
        |> element("input[phx-value-filter='manufacturer']")
        |> render_click()

      assert html =~ "1 results"

      html =
        index_live
        |> element("input[phx-value-filter='manufacturer']")
        |> render_click()

      assert html =~ "Start typing to search"
    end
  end
end
