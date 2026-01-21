# InventoryLocator

Personal inventory system for tracking workshop items with photos and AI-powered search.

Track 1000+ items with precise location codes (Shelf → Bin → Cell), find anything instantly via text search or semantic AI queries, and capture photos from your phone with instant sync to desktop.

## Quick Start (Development)

### Prerequisites

- **Linux** (Ubuntu 22.04+ recommended)
- **PostgreSQL 14+** with pg_trgm extension
- **Erlang/OTP 28.3** and **Elixir 1.19.4** (see `.tool-versions` for asdf)
- **libvips** (for image processing)

**Check versions:**
```bash
psql --version      # PostgreSQL 14+
elixir --version    # Elixir 1.19.4, OTP 28
vips --version      # libvips installed
```

### System Dependencies (Ubuntu/Debian)

```bash
sudo apt install -y postgresql libvips-dev
```

### Setup

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/inventory-locator-service.git
cd inventory-locator-service

# Copy environment template
cp .envrc.example .envrc

# Edit with your database credentials
vim .envrc

# Load environment (requires direnv, or source manually)
direnv allow
# Or: source .envrc

# Setup project (install deps, create db, run migrations)
mix setup

# Start development server
mix phx.server
# Or with IEx: iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) in your browser.

### Environment Variables (Development)

Create `.envrc` with these values:

```bash
export DB_USERNAME=your_db_username
export DB_PASSWORD=your_db_password
export DB_HOST=localhost
export DB_NAME=inventory_locator_dev
export SECRET_KEY_BASE=$(mix phx.gen.secret)

# Optional: AI search
# export GEMINI_API_KEY=your_api_key
```

## Production Deployment

For running on a Raspberry Pi or other always-on server:

**→ See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)**

Covers:
- Hardware requirements (RPi 4 with 2GB+ RAM)
- Step-by-step installation with verification commands
- Systemd service for auto-start
- Maintenance and troubleshooting

## Project Structure

```
├── lib/
│   ├── inventory_locator/        # Business logic
│   │   ├── inventory/            # Items, locations, shelves
│   │   ├── backup/               # Backup system
│   │   └── search/               # Text and AI search
│   └── inventory_locator_web/    # Phoenix web layer
│       └── live/                 # LiveView pages
├── priv/
│   ├── repo/migrations/          # Database migrations
│   └── static/uploads/           # Photo storage
├── bin/
│   └── server                    # Start script for systemd
├── deploy/
│   └── inventory-locator.service # Systemd unit file
└── docs/
    ├── SPEC.md                   # Requirements
    ├── DESIGN.md                 # Architecture
    ├── PLAN.md                   # Implementation status
    └── DEPLOYMENT.md             # Production setup
```

## Key Features

- **Fast item entry**: Add items in under 30 seconds with photo capture
- **Location hierarchy**: Shelf → Bin → Cell structure with string-based entry ("A-3-0")
- **Text search**: Full-text search with fuzzy matching via pg_trgm
- **AI search**: Semantic queries via Gemini API ("where are my soldering tools?")
- **Multi-inventory**: Separate inventories for workshop, household, etc.
- **Backup system**: Local backups with scheduling

## Documentation

| Document | Purpose |
|----------|---------|
| [SPEC.md](docs/SPEC.md) | Requirements and vision |
| [DESIGN.md](docs/DESIGN.md) | Architecture decisions |
| [PLAN.md](docs/PLAN.md) | Implementation status |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Raspberry Pi setup |

## Running Tests

```bash
mix test
```

## License

Private project - not licensed for distribution.
