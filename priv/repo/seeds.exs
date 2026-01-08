alias InventoryLocator.{Repo, Inventory}
require Logger

Logger.info("🌱 Seeding database...")

Repo.delete_all(InventoryLocator.Inventory.ItemType)
Repo.delete_all(InventoryLocator.Inventory.Location)
Repo.delete_all(InventoryLocator.Inventory.Cell)
Repo.delete_all(InventoryLocator.Inventory.Bin)
Repo.delete_all(InventoryLocator.Inventory.Shelf)

Logger.info("Creating items with locations...")

Inventory.create_item_with_location!(
  "A-1-0",
  "M3 Screws",
  150,
  "Assorted lengths, stainless steel"
)

Inventory.create_item_with_location!(
  "A-1-1",
  "M4 Screws",
  200,
  "Assorted lengths, stainless steel"
)

Inventory.create_item_with_location!(
  "A-1-2",
  "M5 Screws",
  100,
  "Assorted lengths, stainless steel"
)

Inventory.create_item_with_location!(
  "A-1-3",
  "Wood Screws",
  75,
  "Phillips head, various sizes"
)

Inventory.create_item_with_location!(
  "A-2-0",
  "Wire Nuts",
  50,
  "Assorted sizes, red and blue"
)

Inventory.create_item_with_location!(
  "A-2-1",
  "Electrical Tape",
  12,
  "Black, 3/4 inch"
)

Inventory.create_item_with_location!(
  "A-2-2",
  "Heat Shrink Tubing",
  30,
  "Various diameters, assorted colors"
)

Inventory.create_item_with_location!(
  "A-3-0",
  "Zip Ties",
  200,
  "Various sizes, black and white"
)

Inventory.create_item_with_location!(
  "A-3-1",
  "Cable Clamps",
  45,
  "Assorted sizes"
)

Inventory.create_item_with_location!(
  "B-1-0",
  "AA Batteries",
  24,
  "Alkaline, various brands"
)

Inventory.create_item_with_location!(
  "B-1-1",
  "AAA Batteries",
  16,
  "Alkaline, various brands"
)

Inventory.create_item_with_location!(
  "B-1-2",
  "9V Batteries",
  8,
  "Alkaline"
)

Inventory.create_item_with_location!(
  "B-2-0",
  "LED Bulbs",
  15,
  "60W equivalent, warm white"
)

Inventory.create_item_with_location!(
  "B-2-1",
  "LED Strip Lights",
  3,
  "5m rolls, RGB, with remote"
)

Inventory.create_item_with_location!(
  "C-1-0",
  "Sandpaper Assortment",
  40,
  "Grits 80-320"
)

Inventory.create_item_with_location!(
  "C-1-1",
  "Steel Wool",
  15,
  "Various grades"
)

Inventory.create_item_with_location!(
  "C-2-0",
  "Wood Glue",
  3,
  "Titebond Original, 16oz bottles"
)

Inventory.create_item_with_location!(
  "C-2-1",
  "Super Glue",
  10,
  "Cyanoacrylate, gel and liquid"
)

Inventory.create_item_with_location!(
  "C-2-2",
  "Epoxy",
  5,
  "Two-part, 5-minute and 24-hour varieties"
)

Logger.info("✅ Seeding complete!")
