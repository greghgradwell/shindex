alias InventoryLocator.Accounts.InviteCode
alias InventoryLocator.Accounts.User
alias InventoryLocator.Inventory
alias InventoryLocator.Repo

require Logger

Logger.info("Seeding database...")

Repo.delete_all(InventoryLocator.Inventory.ItemInstallation)
Repo.delete_all(InventoryLocator.Inventory.ItemType)
Repo.delete_all(InventoryLocator.Inventory.Location)
Repo.delete_all(InventoryLocator.Inventory.Bin)
Repo.delete_all(InventoryLocator.Inventory.Shelf)
Repo.delete_all(InventoryLocator.Inventory.Inv)

Repo.delete_all(InventoryLocator.Accounts.UserIdentity)
Repo.delete_all(InviteCode)
Repo.delete_all(User)

Logger.info("Creating seed admin user...")

{:ok, admin_user} =
  %User{}
  |> User.changeset(%{name: "Seed Admin", role: "admin"})
  |> Repo.insert()

Logger.info("Creating Test inventory with sample items...")

{:ok, test_inv} =
  Inventory.create_inventory(%{
    name: "Test",
    description: "Test/development inventory",
    user_id: admin_user.id
  })

Inventory.create_item_with_location!(%{
  inventory_id: test_inv.id,
  location_code: "A-1",
  name: "M3 Screws",
  quantity: 150,
  description: "Stainless steel, assorted lengths"
})

Inventory.create_item_with_location!(%{
  inventory_id: test_inv.id,
  location_code: "A-2",
  name: "Wire Nuts",
  quantity: 50,
  manufacturer: "3M",
  model: "T/R+"
})

Inventory.create_item_with_location!(%{
  inventory_id: test_inv.id,
  location_code: "B-1",
  name: "AA Batteries",
  quantity: 24,
  manufacturer: "Duracell",
  model: "Powerboost"
})

Inventory.create_item_with_location!(%{
  inventory_id: test_inv.id,
  location_code: "B-2",
  name: "LED Bulbs",
  quantity: 15,
  description: "60W equivalent, warm white",
  model: "LED-A19-60W"
})

Inventory.create_item_with_location!(%{
  inventory_id: test_inv.id,
  location_code: "C-1",
  name: "Wood Glue",
  quantity: 3,
  manufacturer: "Titebond",
  model: "Original"
})

Inventory.create_item_with_location!(%{
  inventory_id: test_inv.id,
  location_code: "C-2",
  name: "ICM-20948 breakout board",
  quantity: 3,
  manufacturer: "Sparkfun"
})

Logger.info("Creating seed admin invite code...")

%InviteCode{}
|> InviteCode.changeset(%{
  code: InviteCode.generate_code(),
  role: "admin",
  expires_at: DateTime.add(DateTime.utc_now(), 365, :day),
  created_by_id: admin_user.id
})
|> Repo.insert!()
|> then(&Logger.info("Admin invite code: #{&1.code}"))

Logger.info("Seeding complete!")
