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
    sudo cp deploy/inventory-locator.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable inventory-locator
    @echo "Service installed. Run 'just start' to start it."

# Uninstall the systemd service
uninstall-service:
    sudo systemctl stop inventory-locator || true
    sudo systemctl disable inventory-locator || true
    sudo rm -f /etc/systemd/system/inventory-locator.service
    sudo systemctl daemon-reload
    @echo "Service uninstalled."

# Run database migrations
migrate:
    source .envrc && mix ecto.migrate

# Reset database (WARNING: deletes all data)
db-reset:
    source .envrc && mix ecto.drop && mix ecto.create && mix ecto.migrate

# Run tests
test:
    source .envrc && mix test

# Run tests with coverage
test-cover:
    source .envrc && mix test --cover

# Check code quality
check:
    source .envrc && mix format --check-formatted && mix credo --strict

# Format code
format:
    mix format

# Update dependencies
deps:
    mix deps.get
