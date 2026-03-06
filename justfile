# Shindex commands

# Default recipe: show available commands
default:
    @just --list

# Start the systemd service
start:
    sudo systemctl start shindex

# Stop the systemd service
stop:
    sudo systemctl stop shindex

# Restart the systemd service
restart:
    sudo systemctl restart shindex

# Show service status
status:
    @systemctl status shindex --no-pager || true

# View live logs
logs:
    sudo journalctl -u shindex -f

# View last 50 log lines
logs-tail:
    sudo journalctl -u shindex -n 50 --no-pager

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
    sudo cp deploy/shindex.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable shindex

# Seed database with test inventory (WARNING: deletes existing data)
seed:
    mix run priv/repo/seeds.exs
