defmodule InventoryLocatorWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      use InventoryLocatorWeb, :verified_routes

      import InventoryLocatorWeb.ConnCase
      import Phoenix.ConnTest
      import Plug.Conn
      # The default endpoint for testing
      @endpoint InventoryLocatorWeb.Endpoint

      # Import conveniences for testing with connections
    end
  end

  setup tags do
    InventoryLocator.DataCase.setup_sandbox(tags)
    inventory = InventoryLocator.DataCase.create_test_inventory(%{})
    user = InventoryLocator.DataCase.create_test_user(%{name: "Test Admin", role: "admin"})

    conn =
      Plug.Test.init_test_session(Phoenix.ConnTest.build_conn(), %{
        inventory_id: inventory.id,
        user_id: user.id
      })

    {:ok, conn: conn, inventory: inventory, user: user}
  end
end
