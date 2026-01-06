defmodule InventoryLocatorWeb.PageController do
  use InventoryLocatorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
