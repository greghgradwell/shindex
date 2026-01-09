defmodule InventoryLocatorWeb.ItemLive.ShowTest do
  use InventoryLocatorWeb.ConnCase

  import Phoenix.LiveViewTest
  alias InventoryLocator.{Inventory, Repo}

  describe "Show" do
    test "displays item details", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test Item", 5, "Description")

      {:ok, _show_live, html} = live(conn, ~p"/items/#{item.id}")

      assert html =~ "Test Item"
      assert html =~ "A-1-1"
      assert html =~ "Description"
    end

    test "shows quantity in display", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 7, "Desc")

      {:ok, _show_live, html} = live(conn, ~p"/items/#{item.id}")

      assert html =~ "7"
    end

    test "increment quantity updates display", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      html =
        show_live
        |> element("button[phx-click='increment_quantity']")
        |> render_click()

      assert html =~ "6"
    end

    test "decrement quantity updates display", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      html =
        show_live
        |> element("button[phx-click='decrement_quantity']")
        |> render_click()

      assert html =~ "4"
    end

    test "archive button archives item and keeps location", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      html =
        show_live
        |> element("button[phx-click='archive']")
        |> render_click()

      assert html =~ "Archived"
      assert html =~ "Restore Item"

      updated = Inventory.get_item_type!(item.id)
      assert updated.archived == true
      assert updated.location_id == item.location_id
    end

    test "archived item shows restore button instead of archive", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")
      {:ok, _archived} = Inventory.archive_item_type(item)

      {:ok, _show_live, html} = live(conn, ~p"/items/#{item.id}")

      assert html =~ "Restore Item"
      refute html =~ "Archive Item"
    end

    test "archived item does not show quantity controls", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")
      {:ok, _archived} = Inventory.archive_item_type(item)

      {:ok, _show_live, html} = live(conn, ~p"/items/#{item.id}")

      refute html =~ "increment_quantity"
      refute html =~ "decrement_quantity"
    end

    test "shows restore modal on restore button click", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")
      {:ok, _archived} = Inventory.archive_item_type(item)

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      html =
        show_live
        |> element("button[phx-click='show_restore_modal']")
        |> render_click()

      assert html =~ "modal-open"
      assert html =~ "Location Code"
    end

    test "restore modal closes on cancel", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")
      {:ok, _archived} = Inventory.archive_item_type(item)

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      show_live
      |> element("button[phx-click='show_restore_modal']")
      |> render_click()

      html =
        show_live
        |> element("button[phx-click='close_restore_modal']")
        |> render_click()

      refute html =~ "modal-open"
    end

    test "restore item to empty location succeeds", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")
      {:ok, _archived} = Inventory.archive_item_type(item)

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      show_live
      |> element("button[phx-click='show_restore_modal']")
      |> render_click()

      html =
        show_live
        |> form("form", %{location_code: "B-2-1", quantity: "3"})
        |> render_submit()

      refute html =~ "modal-open"
      refute html =~ "Archived"

      updated = Inventory.get_item_type!(item.id)
      assert updated.archived == false
      assert updated.quantity == 3
    end

    test "restore item to occupied location shows warning", %{conn: conn} do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-1", "Item 1", 5, "Desc")
      {:ok, item2} = Inventory.create_item_with_location("A-2-1", "Item 2", 3, "Desc")

      {:ok, _archived} = Inventory.archive_item_type(item2)

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item2.id}")

      show_live
      |> element("button[phx-click='show_restore_modal']")
      |> render_click()

      html =
        show_live
        |> form("form", %{location_code: "A-1-1"})
        |> render_change()

      assert html =~ "has 1 active item"
      assert html =~ "co-located"
    end

    test "restore to occupied location allows proceeding", %{conn: conn} do
      {:ok, _item1} = Inventory.create_item_with_location("A-1-1", "Item 1", 5, "Desc")
      {:ok, item2} = Inventory.create_item_with_location("A-2-1", "Item 2", 3, "Desc")

      {:ok, _archived} = Inventory.archive_item_type(item2)

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item2.id}")

      show_live
      |> element("button[phx-click='show_restore_modal']")
      |> render_click()

      html =
        show_live
        |> form("form", %{location_code: "A-1-1", quantity: "2"})
        |> render_submit()

      refute html =~ "Archived"

      updated = Inventory.get_item_type!(item2.id)
      assert updated.archived == false
      assert updated.quantity == 2
    end

    test "shows manufacturer and model when present", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")
      item = Repo.preload(item, :location)

      {:ok, updated} =
        Inventory.update_item_type(item, %{manufacturer: "Acme Corp", model: "X-2000"})

      {:ok, _show_live, html} = live(conn, ~p"/items/#{updated.id}")

      assert html =~ "Acme Corp"
      assert html =~ "X-2000"
    end

    test "has back to search link", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")

      {:ok, _show_live, html} = live(conn, ~p"/items/#{item.id}")

      assert html =~ "Back to Search"
      assert html =~ "/items"
    end

    test "validates location code format on restore", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")
      {:ok, _archived} = Inventory.archive_item_type(item)

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      show_live
      |> element("button[phx-click='show_restore_modal']")
      |> render_click()

      html =
        show_live
        |> form("form", %{location_code: "invalid", quantity: "1"})
        |> render_submit()

      assert html =~ "modal-open"

      updated = Inventory.get_item_type!(item.id)
      assert updated.archived == true
    end

    test "decrement from quantity 1 shows archive modal", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 1, "Desc")

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      html =
        show_live
        |> element("button[phx-click='decrement_quantity']")
        |> render_click()

      assert html =~ "modal-open"
      assert html =~ "Archive Item?"
      assert html =~ "Setting quantity to 0 will archive"
    end

    test "entering 0 quantity shows archive modal", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 5, "Desc")

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      html =
        show_live
        |> form("#quantity-update-form", %{quantity: "0"})
        |> render_change()

      assert html =~ "modal-open"
      assert html =~ "Archive Item?"
    end

    test "confirm archive from quantity modal archives item", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 1, "Desc")

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      show_live
      |> element("button[phx-click='decrement_quantity']")
      |> render_click()

      html =
        show_live
        |> element("button[phx-click='confirm_archive_from_quantity']")
        |> render_click()

      refute html =~ "modal-open"
      assert html =~ "Archived"

      updated = Inventory.get_item_type!(item.id)
      assert updated.archived == true
      assert updated.quantity == 0
    end

    test "cancel archive from quantity modal keeps item active", %{conn: conn} do
      {:ok, item} = Inventory.create_item_with_location("A-1-1", "Test", 1, "Desc")

      {:ok, show_live, _html} = live(conn, ~p"/items/#{item.id}")

      show_live
      |> element("button[phx-click='decrement_quantity']")
      |> render_click()

      html =
        show_live
        |> element("button[phx-click='cancel_archive_from_quantity']")
        |> render_click()

      refute html =~ "modal-open"
      refute html =~ "Archived"

      updated = Inventory.get_item_type!(item.id)
      assert updated.archived == false
      assert updated.quantity == 1
    end
  end
end
