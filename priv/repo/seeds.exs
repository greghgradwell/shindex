alias InventoryLocator.Inventory
alias InventoryLocator.Repo

require Logger

Logger.info("🌱 Seeding database...")

Repo.delete_all(InventoryLocator.Inventory.ItemInstallation)
Repo.delete_all(InventoryLocator.Inventory.ItemType)
Repo.delete_all(InventoryLocator.Inventory.Location)
Repo.delete_all(InventoryLocator.Inventory.Bin)
Repo.delete_all(InventoryLocator.Inventory.Shelf)
Repo.delete_all(InventoryLocator.Inventory.Inv)

Logger.info("Creating Test inventory with sample items...")

{:ok, test_inv} = Inventory.create_inventory(%{name: "Test", description: "Test/development inventory"})

Inventory.create_item_with_location!(test_inv.id, "A-1", "M3 Screws", 150, "Assorted lengths, stainless steel")
Inventory.create_item_with_location!(test_inv.id, "A-2", "M4 Screws", 200, "Assorted lengths, stainless steel")
Inventory.create_item_with_location!(test_inv.id, "A-3", "M5 Screws", 100, "Assorted lengths, stainless steel")
Inventory.create_item_with_location!(test_inv.id, "A-4", "Wood Screws", 75, "Phillips head, various sizes")
Inventory.create_item_with_location!(test_inv.id, "A-5", "Wire Nuts", 50, "Assorted sizes, red and blue")
Inventory.create_item_with_location!(test_inv.id, "A-6", "Electrical Tape", 12, "Black, 3/4 inch")
Inventory.create_item_with_location!(test_inv.id, "A-7", "Heat Shrink Tubing", 30, "Various diameters, assorted colors")
Inventory.create_item_with_location!(test_inv.id, "A-8", "Zip Ties", 200, "Various sizes, black and white")
Inventory.create_item_with_location!(test_inv.id, "A-9", "Cable Clamps", 45, "Assorted sizes")
Inventory.create_item_with_location!(test_inv.id, "B-1", "AA Batteries", 24, "Alkaline, various brands")
Inventory.create_item_with_location!(test_inv.id, "B-2", "AAA Batteries", 16, "Alkaline, various brands")
Inventory.create_item_with_location!(test_inv.id, "B-3", "9V Batteries", 8, "Alkaline")
Inventory.create_item_with_location!(test_inv.id, "B-4", "LED Bulbs", 15, "60W equivalent, warm white")
Inventory.create_item_with_location!(test_inv.id, "B-5", "LED Strip Lights", 3, "5m rolls, RGB, with remote")
Inventory.create_item_with_location!(test_inv.id, "C-1", "Sandpaper Assortment", 40, "Grits 80-320")
Inventory.create_item_with_location!(test_inv.id, "C-2", "Steel Wool", 15, "Various grades")
Inventory.create_item_with_location!(test_inv.id, "C-3", "Wood Glue", 3, "Titebond Original, 16oz bottles")
Inventory.create_item_with_location!(test_inv.id, "C-4", "Super Glue", 10, "Cyanoacrylate, gel and liquid")
Inventory.create_item_with_location!(test_inv.id, "C-5", "Epoxy", 5, "Two-part, 5-minute and 24-hour varieties")

Logger.info("✅ Seeding complete!")
