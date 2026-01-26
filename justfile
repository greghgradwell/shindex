# Inventory Locator Service commands

# Default recipe: show available commands
default:
    @just --list

# Start the systemd service
start:
    sudo systemctl start inventory-locator

# Stop the systemd service
stop:
    sudo systemctl stop inventory-locator

# Restart the systemd service
restart:
    sudo systemctl restart inventory-locator

# Show service status
status:
    @systemctl status inventory-locator --no-pager || true

# View live logs
logs:
    sudo journalctl -u inventory-locator -f

# View last 50 log lines
logs-tail:
    sudo journalctl -u inventory-locator -n 50 --no-pager

# Run development server (stops service first)
dev:
    @just stop 2>/dev/null || true
    source .envrc && iex -S mix phx.server

# Run development server without iex
server:
    @just stop 2>/dev/null || true
    source .envrc && mix phx.server

# Install/reinstall the systemd service
install-service:
    sudo cSeed database with Test inventory (WARNING: deletes existing data)
seed:
    mix run priv/repo/seeds.exs
