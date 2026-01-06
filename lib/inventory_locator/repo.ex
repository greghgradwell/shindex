defmodule InventoryLocator.Repo do
  use Ecto.Repo,
    otp_app: :inventory_locator,
    adapter: Ecto.Adapters.Postgres
end
