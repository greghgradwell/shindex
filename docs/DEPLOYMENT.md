# Raspberry Pi Deployment Guide

Deploy Shindex to a Raspberry Pi for always-on workshop access.

## Setup Checklist

Use this checklist to track progress. Each step has detailed instructions below.

- [ ] **Prerequisites**: Raspberry Pi OS 64-bit installed, SSH access working
- [ ] **Step 1**: System update and core packages
- [ ] **Step 2**: PostgreSQL installation and configuration
- [ ] **Step 3**: Install asdf version manager
- [ ] **Step 4**: Install Erlang (30-60 min compile time on Pi)
- [ ] **Step 5**: Install Elixir
- [ ] **Step 6**: Clone repository and install dependencies
- [ ] **Step 7**: Configure environment variables
- [ ] **Step 8**: Setup database
- [ ] **Step 9**: Build assets
- [ ] **Step 10**: Create and enable systemd service
- [ ] **Step 11**: Verify application starts on boot
- [ ] **Final**: Test from phone browser

---

## Software Versions

**Check [README.md](../README.md) for required Erlang and Elixir versions.** The project includes a `.tool-versions` file for asdf users—after installing the asdf plugins, you can run `asdf install` to get the correct versions automatically.

This guide uses `<erlang-version>` and `<elixir-version>` placeholders—substitute the actual versions from README or `.tool-versions`.

---

## Hardware Requirements

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| **Model** | RPi 4 (2GB) | RPi 4 (4GB) | ARM64 required for modern Erlang |
| **RAM** | 2GB | 4GB | 2GB works fine for single user |
| **Storage** | 16GB microSD | 32GB microSD | Quality card (Samsung EVO, SanDisk Extreme) |
| **Network** | WiFi or Ethernet | Either works | Local network access for phone sync |

**Why these requirements:**
- **2GB RAM works**: Single user, database mostly cached in RAM, image processing is sequential
- **ARM64**: Modern Erlang/OTP with JIT compiler provides 2-3x performance boost over ARM32
- **microSD is fine**: With ~1000 items and one user, I/O is not a bottleneck; use quality card for longevity
- **No SSD needed**: PostgreSQL queries return in <50ms on microSD, imperceptible for single user

---

## Prerequisites

### Raspberry Pi OS Installation

1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Choose **Raspberry Pi OS Lite (64-bit)** - no desktop needed
3. Click the gear icon (⚙️) to configure:
   - Set hostname (e.g., `inventory`)
   - Enable SSH with password authentication
   - Set username/password (e.g., `pi`)
   - Configure WiFi if needed
4. Write to microSD card and boot the Pi

**Verify SSH access:**
```bash
ssh pi@inventory.local
# Or use IP address: ssh pi@192.168.x.x
```

**Expected:** You're logged into the Pi terminal.

---

## Step 1: System Update and Core Packages

**Command:**
```bash
sudo apt update && sudo apt upgrade -y
```

**Then install build tools and zsh:**
```bash
sudo apt install -y \
  build-essential \
  autoconf \
  m4 \
  libncurses5-dev \
  libssl-dev \
  libwxgtk3.2-dev \
  libvips-dev \
  libvips42 \
  git \
  curl \
  zsh
```

**Set zsh as default shell:**
```bash
chsh -s $(which zsh)
```

Log out and back in for the shell change to take effect.

**Verify:**
```bash
vips --version
```

**Expected:** `vips-8.x.x` or higher

**If it fails:**
- "Package not found" → Run `sudo apt update` first
- "libwxgtk3.2-dev not found" → Try `libwxgtk3.0-gtk3-dev` on older OS versions

---

## Step 2: PostgreSQL Installation

**Command:**
```bash
sudo apt install -y postgresql postgresql-contrib libpq-dev
```

**Start and enable PostgreSQL:**
```bash
sudo systemctl enable postgresql
sudo systemctl start postgresql
```

**Verify:**
```bash
psql --version
sudo systemctl status postgresql
```

**Expected:**
- `psql (PostgreSQL) 15.x` or higher
- Service shows `active (running)`

**Create database user and database:**
```bash
sudo -u postgres psql <<'EOF'
CREATE USER inventory WITH PASSWORD 'your_secure_password_here';
ALTER USER inventory CREATEDB;
CREATE DATABASE inventory_prod OWNER inventory;
\c inventory_prod
CREATE EXTENSION IF NOT EXISTS pg_trgm;
EOF
```

**Verify:**
```bash
sudo -u postgres psql -c "\l" | grep inventory_prod
```

**Expected:** Line showing `inventory_prod | inventory | ...`

**If it fails:**
- "Role already exists" → User was created previously, skip that line
- "Permission denied" → Ensure you're using `sudo -u postgres`

---

## Step 3: Install asdf Version Manager

**Command:**
```bash
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.zshrc
source ~/.zshrc
```

**Verify:**
```bash
asdf --version
```

**Expected:** `v0.14.0` or similar

**Add Erlang and Elixir plugins:**
```bash
asdf plugin add erlang
asdf plugin add elixir
```

**If it fails:**
- "Command not found" → Run `source ~/.zshrc` again
- "Plugin already added" → Plugin exists, continue to next step

---

## Step 4: Install Erlang

> ⚠️ **This takes 30-60 minutes on a Raspberry Pi 4.** Consider using `screen` or `tmux` so compilation continues if SSH disconnects.

**Start a screen session (recommended):**
```bash
screen -S erlang-build
```

**Install Erlang dependencies and compile:**
```bash
KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac" \
  asdf install erlang <erlang-version>
```

**Verify:**
```bash
asdf global erlang <erlang-version>
erl -version
```

**Expected:** Erlang version output (BEAM emulator)

**If it fails:**
- "OpenSSL not found" → Run `sudo apt install -y libssl-dev`
- "SSH disconnected during build" → Reconnect and run `screen -r erlang-build`
- "Out of memory" → Add swap: `sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`

---

## Step 5: Install Elixir

**Command:**
```bash
asdf install elixir <elixir-version>
asdf global elixir <elixir-version>
```

**Verify:**
```bash
elixir --version
```

**Expected:** Elixir version output showing both Elixir and Erlang/OTP versions

**Install Hex and rebar:**
```bash
mix local.hex --force
mix local.rebar --force
```

---

## Step 6: Clone Repository and Install direnv

**Command:**
```bash
sudo apt install -y direnv
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
source ~/.zshrc
```

**Clone repository:**
```bash
cd ~
git clone https://github.com/YOUR_USERNAME/shindex.git
cd shindex
```

**Install dependencies:**
```bash
mix deps.get
```

**Verify:**
```bash
ls deps/ | head -5
```

**Expected:** List of dependency directories (phoenix, ecto, etc.)

---

## Step 7: Configure Environment

**Copy the environment template:**
```bash
cp .envrc.example .envrc
```

**Generate a secret key:**
```bash
mix phx.gen.secret
```

**Copy the output** - you'll need it below.

**Edit the environment file:**
```bash
vim .envrc
```

Update these values:
```bash
export DB_USERNAME=inventory
export DB_PASSWORD=your_secure_password_here  # From Step 2
export DB_HOST=localhost
export DB_NAME=inventory_prod
export SECRET_KEY_BASE=paste_your_generated_secret_here

# Optional: AI search
# export GEMINI_API_KEY=your_key

# Optional: Local backup path
# export BACKUP_PATH=/home/pi/backups
```

**Secure the file permissions:**
```bash
chmod 600 .envrc
```

**Allow direnv to load the environment:**
```bash
direnv allow
```

**Verify:**
```bash
echo $DB_NAME
```

**Expected:** `inventory_prod`

---

## Step 8: Setup Database

**Create database schema (direnv loads environment automatically):**
```bash
mix ecto.create
mix ecto.migrate
```

**Verify:**
```bash
mix ecto.migrations
```

**Expected:** All migrations show `up` status

**If it fails:**
- "Connection refused" → Check PostgreSQL is running: `sudo systemctl status postgresql`
- "Authentication failed" → Verify DB_PASSWORD in .envrc matches Step 2
- "Database does not exist" → Run `mix ecto.create` first

---

## Step 9: Compile Application

**Compile the application:**
```bash
mix compile
```

**Verify:**
```bash
mix phx.server &
curl -s http://localhost:4000 | head -1
kill %1
```

**Expected:** HTML output starting with `<!DOCTYPE html>`

---

## Step 10: Install Systemd Service

**Copy the service file from the repo:**
```bash
sudo cp deploy/shindex.service /etc/systemd/system/
```

**Enable and start the service:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable shindex
sudo systemctl start shindex
```

**Verify:**
```bash
sudo systemctl status shindex
```

**Expected:** `active (running)`

**Check logs if something is wrong:**
```bash
sudo journalctl -u shindex -f
```

---

## Step 11: Verify Auto-Start

**Reboot the Pi:**
```bash
sudo reboot
```

**Wait 60 seconds, then reconnect:**
```bash
ssh pi@inventory.local
```

**Verify service is running:**
```bash
sudo systemctl status shindex
```

**Expected:** `active (running)` with uptime matching since boot

---

## Final: Test from Phone

1. Ensure your phone is on the same WiFi network as the Pi
2. Open browser and navigate to: `http://inventory.local:4000`
3. If `.local` doesn't work, find the Pi's IP: `hostname -I` and use `http://192.168.x.x:4000`

**Expected:** Shindex homepage loads

**Test photo upload:**
1. Navigate to add new item
2. Use camera to take a photo
3. Photo should appear in the form

---

## Environment Variables Reference

| Variable | Required | Example | Description |
|----------|----------|---------|-------------|
| `DB_USERNAME` | Yes | `inventory` | PostgreSQL username |
| `DB_PASSWORD` | Yes | `your_password` | PostgreSQL password |
| `DB_HOST` | Yes | `localhost` | PostgreSQL host |
| `DB_NAME` | Yes | `inventory_prod` | PostgreSQL database name |
| `SECRET_KEY_BASE` | Yes | 64+ char string | Session encryption (use `mix phx.gen.secret`) |
| `GEMINI_API_KEY` | No | API key | For AI-powered search |
| `BACKUP_PATH` | No | `/home/pi/backups` | Local backup storage |

---

## Maintenance

### Updating the Application

```bash
cd ~/shindex-service
git pull
mix deps.get
mix ecto.migrate
sudo systemctl restart shindex
```

### Viewing Logs

```bash
# Live logs
sudo journalctl -u shindex -f

# Last 100 lines
sudo journalctl -u shindex -n 100

# Logs since last boot
sudo journalctl -u shindex -b
```

### Database Backups

If `BACKUP_PATH` is configured, the application stores backups automatically.

**Manual backup:**
```bash
sudo -u postgres pg_dump inventory_prod > ~/backup_$(date +%Y%m%d).sql
```

**Restore from backup:**
```bash
sudo -u postgres psql inventory_prod < ~/backup_YYYYMMDD.sql
```

### Checking Disk Usage

```bash
# Overall disk usage
df -h

# Database size
sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('inventory_prod'));"

# Uploads folder size
du -sh ~/shindex-service/priv/static/uploads/
```

---

## Troubleshooting

### Service Won't Start

**Check the logs:**
```bash
sudo journalctl -u shindex -n 50
```

**Common issues:**
- "DB_NAME not set" → Verify `.envrc` file exists and has correct values
- "Connection refused" → PostgreSQL not running: `sudo systemctl start postgresql`
- "Secret key base missing" → Ensure SECRET_KEY_BASE is set in `.envrc`

### Can't Connect from Phone

1. **Check service is running:** `sudo systemctl status shindex`
2. **Check firewall:** `sudo ufw status` (if enabled, allow port 4000)
3. **Check Pi's IP:** `hostname -I`
4. **Try IP directly:** `http://192.168.x.x:4000`

### Out of Memory During Compilation

**Add swap space:**
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
# Make permanent:
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Erlang Build Fails

**Common fixes:**
```bash
# Missing SSL
sudo apt install -y libssl-dev

# Missing ncurses
sudo apt install -y libncurses5-dev

# Clean and retry (use your erlang version from README)
rm -rf ~/.asdf/installs/erlang/<erlang-version>
asdf install erlang <erlang-version>
```

### Database Migration Fails

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Check connection manually
psql -U $DB_USERNAME -h $DB_HOST -d $DB_NAME -c "SELECT 1"

# Reset database (WARNING: deletes all data)
mix ecto.drop
mix ecto.create
mix ecto.migrate
```
