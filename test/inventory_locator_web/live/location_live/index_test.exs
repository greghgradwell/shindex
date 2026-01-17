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
      |> element("button[phx-click*='delete_location']")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Inventory.get_location!(item.location.id) end
    end

    test "prevents deletion of occupied location", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 1, "Test")
      item = Repo.preload(item, :location)

      {:ok, _index_live, html} = live(conn, ~p"/locations")

      refute html =~ "delete_location"
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

  describe "create shelf modal" do
    test "opens modal when clicking Create Shelf button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/locations")

      html = view |> element("button", "Create Shelf") |> render_click()

      assert html =~ "Create New Shelf"
      assert html =~ "Shelf Code"
      assert html =~ "Number of Bins"
    end

    test "closes modal on cancel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button", "Create Shelf") |> render_click()
      html = view |> element("button", "Cancel") |> render_click()

      refute html =~ "Create New Shelf"
    end

    test "validates shelf code format", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button", "Create Shelf") |> render_click()
      html = view |> element("form") |> render_change(%{"code" => "123invalid"})

      assert html =~ "Must start with a letter"
    end

    test "accepts valid shelf code", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button", "Create Shelf") |> render_click()
      html = view |> element("form") |> render_change(%{"code" => "VALID_1"})

      refute html =~ "text-error"
    end

    test "creates shelf with specified bins on submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button", "Create Shelf") |> render_click()
      html = view |> element("form") |> render_submit(%{"code" => "newshelf", "bin_count" => "3"})

      assert html =~ "NEWSHELF"
      assert html =~ "Bin 1"
      assert html =~ "Bin 2"
      assert html =~ "Bin 3"

      shelf = Repo.get_by!(Inventory.Shelf, code: "NEWSHELF")
      shelf = Repo.preload(shelf, :bins)
      assert length(shelf.bins) == 3
    end

    test "shows error for duplicate shelf code", %{conn: conn} do
      {:ok, _shelf} = Inventory.create_shelf_with_bins(%{code: "EXISTING"}, 1)
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button", "Create Shelf") |> render_click()
      html = view |> element("form") |> render_submit(%{"code" => "existing", "bin_count" => "1"})

      assert html =~ "has already been taken"
    end
  end

  describe "rename shelf modal" do
    test "opens modal showing current shelf code", %{conn: conn} do
      {:ok, _shelf} = Inventory.create_shelf_with_bins(%{code: "ORIGINAL"}, 1)
      {:ok, view, _html} = live(conn, ~p"/locations")

      html = view |> element("button[phx-click='show_rename_shelf_modal']") |> render_click()

      assert html =~ "Rename Shelf"
      assert html =~ "Current Code"
      assert html =~ "ORIGINAL"
    end

    test "validates new code format", %{conn: conn} do
      {:ok, _shelf} = Inventory.create_shelf_with_bins(%{code: "TEST"}, 1)
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button[phx-click='show_rename_shelf_modal']") |> render_click()
      html = view |> element("form") |> render_change(%{"new_code" => "_invalid"})

      assert html =~ "Must start with a letter"
    end

    test "renames shelf and updates display", %{conn: conn} do
      {:ok, _shelf} = Inventory.create_shelf_with_bins(%{code: "OLDNAME"}, 1)
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button[phx-click='show_rename_shelf_modal']") |> render_click()
      html = view |> element("form") |> render_submit(%{"new_code" => "newname"})

      assert html =~ "NEWNAME"
      refute html =~ "OLDNAME"
      assert Repo.get_by(Inventory.Shelf, code: "NEWNAME")
    end

    test "updates location codes when renaming", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("BEFORE-1-1", "Test", 1, "Desc")
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button[phx-click='show_rename_shelf_modal']") |> render_click()
      view |> element("form") |> render_submit(%{"new_code" => "AFTER"})

      assert Repo.get_by(Inventory.Location, full_code: "AFTER-1-1")
      refute Repo.get_by(Inventory.Location, full_code: "BEFORE-1-1")
    end

    test "shows warning about affected locations", %{conn: conn} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(%{code: "WARN"}, 2)
      shelf = Repo.preload(shelf, :bins)
      Inventory.add_cell_to_bin(hd(shelf.bins))

      {:ok, view, _html} = live(conn, ~p"/locations")

      html = view |> element("button[phx-click='show_rename_shelf_modal']") |> render_click()

      assert html =~ "This will update 3 location code(s)"
    end

    test "shows error when renaming to existing code", %{conn: conn} do
      {:ok, shelf1} = Inventory.create_shelf_with_bins(%{code: "FIRST"}, 1)
      {:ok, _shelf2} = Inventory.create_shelf_with_bins(%{code: "SECOND"}, 1)
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button[phx-click='show_rename_shelf_modal'][phx-value-id='#{shelf1.id}']") |> render_click()
      html = view |> element("form") |> render_submit(%{"new_code" => "SECOND"})

      assert html =~ "already exists"
    end
  end

  describe "delete shelf" do
    test "shows delete button on shelf row", %{conn: conn} do
      {:ok, _shelf} = Inventory.create_shelf_with_bins(%{code: "DELETE"}, 1)
      {:ok, _view, html} = live(conn, ~p"/locations")

      assert html =~ "phx-click=\"delete_shelf\""
      assert html =~ "Delete shelf DELETE"
    end

    test "deletes empty shelf on confirm", %{conn: conn} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(%{code: "EMPTY"}, 1)
      {:ok, view, _html} = live(conn, ~p"/locations")

      html = view |> element("button[phx-click='delete_shelf']") |> render_click()

      refute html =~ "EMPTY"
      assert Repo.get(Inventory.Shelf, shelf.id) == nil
    end

    test "refuses to delete shelf with items", %{conn: conn} do
      {:ok, _item} = Inventory.create_item_with_location("OCCUPIED-1-1", "Test", 1, "Desc")
      shelf = Repo.get_by!(Inventory.Shelf, code: "OCCUPIED")
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button[phx-click='delete_shelf']") |> render_click()

      assert Repo.get(Inventory.Shelf, shelf.id)
      assert render(view) =~ "OCCUPIED"
    end
  end

  describe "add bin" do
    test "adds bin to shelf", %{conn: conn} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(%{code: "ADDBIN"}, 1)
      {:ok, view, _html} = live(conn, ~p"/locations")

      html = view |> element("button[phx-click='add_bin']") |> render_click()

      assert html =~ "Bin 2"

      shelf = Repo.preload(shelf, :bins, force: true)
      assert length(shelf.bins) == 2
    end
  end

  describe "add cell" do
    test "adds cell to bin", %{conn: conn} do
      {:ok, shelf} = Inventory.create_shelf_with_bins(%{code: "ADDCELL"}, 1)
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("button[phx-click='add_cell']") |> render_click()

      shelf = Repo.preload(shelf, [bins: :cells], force: true)
      bin = hd(shelf.bins)
      assert length(bin.cells) == 2
      assert bin.cells |> Enum.map(& &1.code) |> Enum.sort() == ["1", "2"]
    end
  end

  describe "show cells toggle" do
    test "toggle is visible and checked by default", %{conn: conn} do
      {:ok, _shelf} = Inventory.create_shelf_with_bins(%{code: "TOGGLE"}, 1)
      {:ok, _view, html} = live(conn, ~p"/locations")

      assert html =~ "Show cells"
      assert html =~ "checked"
    end

    test "hides cells when toggled off", %{conn: conn} do
      {:ok, _shelf} = Inventory.create_shelf_with_bins(%{code: "TOGGLE"}, 1)
      {:ok, view, html} = live(conn, ~p"/locations")

      assert html =~ "Add cell"

      html = view |> element("input[phx-click='toggle_cells']") |> render_click()

      refute html =~ "Add cell"
      assert html =~ "Bin 1"
    end

    test "shows cells when toggled back on", %{conn: conn} do
      {:ok, _shelf} = Inventory.create_shelf_with_bins(%{code: "TOGGLE"}, 1)
      {:ok, view, _html} = live(conn, ~p"/locations")

      view |> element("input[phx-click='toggle_cells']") |> render_click()
      html = view |> element("input[phx-click='toggle_cells']") |> render_click()

      assert html =~ "Add cell"
    end
  end
end
