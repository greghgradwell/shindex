# Raspberry Pi Database Reset Instructions

This document provides instructions for resetting the database on the Raspberry Pi server when deploying a version with consolidated migrations.

## When This Is Needed

The migrations were consolidated on January 24, 2026 to remove the obsolete "Cell" layer from the location hierarchy. If your Pi has an older database with the original migration chain, you'll need to reset it.

## Before You Begin

**⚠️ WARNING: This will delete all data in the database!**

1. **Create a backup first** (if you have data worth preserving):
   ```bash
   # On the Pi
   cd ~/shindex
   pg_dump -U $DB_USERNAME $DB_NAME | gzip > ~/backup_before_reset_$(date +%Y%m%d).sql.gz
   ```

2. **Backup photos** (if any):
   ```bash
   tar -czvf ~/photos_backup_$(date +%Y%m%d).tar.gz priv/static/uploads/
   ```

## Reset Procedure

### Option A: Using Mix (Recommended)

```bash
# SSH into the Pi
ssh pi@your-pi-hostname

# Navigate to the project directory
cd ~/shindex

# Pull the latest code
git pull origin main

# Stop the service
sudo systemctl stop shindex

# Reset the database (drops, creates, and migrates)
source .envrc  # or however you load env vars
mix ecto.reset

# Restart the service
sudo systemctl start shindex

# Verify it's running
sudo systemctl status shindex
curl http://localhost:4000
```

### Option B: Manual Database Reset

If `mix ecto.reset` fails, you can manually reset:

```bash
# Drop and recreate the database
sudo -u postgres psql -c "DROP DATABASE IF EXISTS inventory_locator_prod;"
sudo -u postgres psql -c "CREATE DATABASE inventory_locator_prod OWNER your_db_user;"

# Run migrations
mix ecto.migrate
```

## Post-Reset Steps

1. **Seed data** (optional):
   ```bash
   mix run priv/repo/seeds.exs
   ```

2. **Restore photos** (if backed up):
   ```bash
   tar -xzvf ~/photos_backup_*.tar.gz -C .
   ```

3. **Verify the application**:
   - Visit the web UI
   - Create a test shelf and item
   - Confirm location codes are now 2-part format (e.g., "A-1" instead of "A-1-1")

## Troubleshooting

### "relation does not exist" errors

The schema_migrations table may have old migration IDs. Reset clears this.

### Extension errors

If pg_trgm extension fails:
```bash
sudo -u postgres psql -d inventory_locator_prod -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
```

### Permission errors

Ensure your database user has the correct permissions:
```bash
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE inventory_locator_prod TO your_db_user;"
```

## Version History

| Date | Change |
|------|--------|
| 2026-01-24 | Consolidated migrations, removed Cell layer |
