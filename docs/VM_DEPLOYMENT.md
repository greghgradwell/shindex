# GCP VM Deployment Guide

Deploy Inventory Locator to the GCP VM at `sharehub.nextdaynet.com` as a production
service alongside the existing Jitsi installation.

This guide uses Claude Code on the VM to handle configuration and troubleshooting.

## Setup Checklist

- [ ] **Prerequisites**: SSH into VM, DNS record for `sharehub.nextdaynet.com` points to VM IP
- [ ] **Step 1**: System packages and libvips
- [ ] **Step 2**: PostgreSQL installation and database creation
- [ ] **Step 3**: Install asdf version manager
- [ ] **Step 4**: Install Erlang (~10 min on VM, much faster than Pi)
- [ ] **Step 5**: Install Elixir
- [ ] **Step 6**: Clone repository and install Claude Code
- [ ] **Step 7**: Configure production environment
- [ ] **Step 8**: Build production release
- [ ] **Step 9**: Install and start systemd service
- [ ] **Step 10**: Configure Nginx and SSL
- [ ] **Step 11**: Migrate data from Pi
- [ ] **Step 12**: Update OAuth callback URLs
- [ ] **Final**: Verify everything works end-to-end

---

## Software Versions

**Check `.tool-versions` in the repository root for required Erlang and Elixir versions.**
The project includes a `.tool-versions` file — after adding the asdf plugins, run `asdf install`
to get the correct versions automatically.

---

## Prerequisites

The VM should already be provisioned and accessible. Verify before starting:

```bash
ssh ubuntu@sharehub.nextdaynet.com
```

**Verify DNS:**
```bash
curl -s https://api.ipify.org  # Get VM's public IP
# Then confirm: dig sharehub.nextdaynet.com +short
```

**Expected:** VM's public IP matches the DNS record for `sharehub.nextdaynet.com`.

If DNS isn't set yet, add an A record for `sharehub.nextdaynet.com` pointing to the VM's
external IP before continuing — certbot needs it for SSL certificate issuance.

---

## Step 1: System Packages

**Command:**
```bash
sudo apt update && sudo apt upgrade -y
```

**Install required packages:**
```bash
sudo apt install -y \
  build-essential \
  autoconf \
  m4 \
  libncurses5-dev \
  libssl-dev \
  libwxgtk3.2-dev \
  libvips-dev \
  git \
  curl \
  zsh \
  direnv \
  certbot \
  python3-certbot-nginx
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
- `libwxgtk3.2-dev not found` → Try `libwxgtk3.0-gtk3-dev` (older Ubuntu)
- `libvips-dev not found` → Run `sudo apt update` first

---

## Step 2: PostgreSQL Installation

**Install PostgreSQL:**
```bash
sudo apt install -y postgresql postgresql-contrib libpq-dev
sudo systemctl enable postgresql
sudo systemctl start postgresql
```

**Create a database user and databases:**
```bash
sudo -u postgres createuser --superuser ubuntu
createdb inventory_locator_prod
createdb inventory_locator_dev
```

**Verify:**
```bash
psql --version
psql -d inventory_locator_prod -c "SELECT 1"
```

**Expected:** `psql (PostgreSQL) 14.x` or higher, then `(1 row)`.

**If it fails:**
- `Role "ubuntu" already exists` → Already created, skip that line
- `Connection refused` → Run `sudo systemctl start postgresql`

---

## Step 3: Install asdf Version Manager

**Command:**
```bash
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.zshrc
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
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

---

## Step 4: Install Erlang

> This takes ~10 minutes on the VM (much faster than on the Pi).

**Command:**
```bash
cd ~/inventory-locator-service  # or wherever you'll clone it
asdf install erlang  # reads version from .tool-versions
```

If you haven't cloned the repo yet, specify the version explicitly:
```bash
asdf install erlang 28.3
asdf global erlang 28.3
```

**Verify:**
```bash
erl -version
```

**Expected:** Erlang version output

**If it fails:**
- `OpenSSL not found` → `sudo apt install -y libssl-dev`
- `wxWidgets not found` → `sudo apt install -y libwxgtk3.2-dev`

---

## Step 5: Install Elixir

**Command:**
```bash
asdf install elixir  # reads from .tool-versions, or:
# asdf install elixir 1.19.4-otp-28
# asdf global elixir 1.19.4-otp-28
```

**Verify:**
```bash
elixir --version
```

**Expected:** Elixir version with matching OTP version

**Install Hex and rebar:**
```bash
mix local.hex --force
mix local.rebar --force
```

---

## Step 6: Clone Repository and Install Claude Code

**Clone the repository:**
```bash
git clone git@github.com:greghgradwell/inventory-locator-service.git ~/inventory-locator-service
cd ~/inventory-locator-service
```

If SSH key isn't configured on the VM:
```bash
# Option A: Add VM's SSH key to GitHub
ssh-keygen -t ed25519 -C "inventory-vm"
cat ~/.ssh/id_ed25519.pub  # Add this to GitHub Settings → SSH Keys

# Option B: Use HTTPS clone instead
git clone https://github.com/greghgradwell/inventory-locator-service.git ~/inventory-locator-service
```

**Install Claude Code:**
```bash
npm install -g @anthropic-ai/claude-code
```

If npm isn't installed:
```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
npm install -g @anthropic-ai/claude-code
```

**Start Claude Code in the project directory:**
```bash
cd ~/inventory-locator-service
claude
```

From this point you can use Claude Code to handle configuration, troubleshooting, and
ongoing development via SSH tunnel (see Development Workflow below).

---

## Step 7: Configure Production Environment

**Copy the production environment template:**
```bash
cp deploy/.envrc.example .envrc
```

**Generate a secret key:**
```bash
mix phx.gen.secret
```

Copy the output — you'll need it for `SECRET_KEY_BASE`.

**Edit the environment file:**
```bash
nano .envrc  # or vim
```

Required values:
```bash
export DATABASE_URL=ecto://ubuntu@localhost/inventory_locator_prod
export SECRET_KEY_BASE=paste_your_generated_secret_here
export PHX_HOST=sharehub.nextdaynet.com

export GITHUB_CLIENT_ID=your_github_client_id
export GITHUB_CLIENT_SECRET=your_github_client_secret

export LINKEDIN_CLIENT_ID=your_linkedin_client_id
export LINKEDIN_CLIENT_SECRET=your_linkedin_client_secret

export BACKUP_PATH=/home/ubuntu/inventory-backups
```

> **Note:** `DATABASE_URL` uses `ubuntu@localhost` because we created a superuser matching
> the ubuntu OS user — no password needed for local connections.

**Secure the file:**
```bash
chmod 600 .envrc
direnv allow
```

**Verify:**
```bash
echo $PHX_HOST
```

**Expected:** `sharehub.nextdaynet.com`

---

## Step 8: Build Production Release

**Install production dependencies:**
```bash
MIX_ENV=prod mix deps.get --only prod
```

**Build assets:**
```bash
MIX_ENV=prod mix assets.deploy
```

**Build the release:**
```bash
MIX_ENV=prod mix release
```

**Verify:**
```bash
ls _build/prod/rel/inventory_locator/bin/
```

**Expected:** `inventory_locator` binary listed

**If it fails:**
- `libvips not found at runtime` → `sudo apt install -y libvips42`
- Asset build errors → Check Node.js is installed: `node --version`

---

## Step 9: Install and Start Systemd Service

**Copy and install the service file:**
```bash
sudo cp deploy/inventory-locator.service /etc/systemd/system/
```

The service file references `/home/ubuntu/inventory-locator-service` as the working directory.
If you cloned to a different path, update accordingly:
```bash
sudo nano /etc/systemd/system/inventory-locator.service
```

**Run database migrations:**
```bash
source .envrc
PHX_SERVER=false _build/prod/rel/inventory_locator/bin/inventory_locator eval "InventoryLocator.Release.migrate()"
```

**Enable and start the service:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable inventory-locator
sudo systemctl start inventory-locator
```

**Verify:**
```bash
sudo systemctl status inventory-locator
```

**Expected:** `active (running)`

**Check logs if something is wrong:**
```bash
sudo journalctl -u inventory-locator -f
```

---

## Step 10: Configure Nginx and SSL

**Copy the Nginx config:**
```bash
sudo cp deploy/nginx.conf /etc/nginx/sites-available/sharehub.nextdaynet.com
sudo ln -s /etc/nginx/sites-available/sharehub.nextdaynet.com \
           /etc/nginx/sites-enabled/sharehub.nextdaynet.com
```

**Test the config syntax:**
```bash
sudo nginx -t
```

**Expected:** `syntax is ok` and `test is successful`

**Get SSL certificate:**
```bash
sudo certbot --nginx -d sharehub.nextdaynet.com
```

Certbot will modify the Nginx config to add SSL. When prompted, choose to redirect HTTP to HTTPS.

**Reload Nginx:**
```bash
sudo systemctl reload nginx
```

**Verify:**
```bash
curl -I https://sharehub.nextdaynet.com
```

**Expected:** `HTTP/2 200` response

**If it fails:**
- `Port 80 already in use` → Check what's using it: `sudo ss -tlnp | grep :80`
- `Domain not found` → DNS hasn't propagated yet, wait and retry
- `Connection refused on port 4000` → Inventory service not running: `sudo systemctl start inventory-locator`

---

## Step 11: Migrate Data from Pi

**Run this on the Pi** (not the VM):
```bash
cd ~/Documents/Github/inventory-locator-service
bin/migrate-to-vm
```

This script:
1. Dumps the Pi's database
2. Copies it to the VM via scp
3. Restores into `inventory_locator_prod`
4. Rsyncs all uploaded photos
5. Rsyncs backups (if any)

**After running, verify on the VM:**
```bash
psql -d inventory_locator_prod -c "SELECT COUNT(*) FROM item_types"
ls priv/static/uploads/ | wc -l
```

**Expected:** Item count and photo count matching what was on the Pi.

**If ssh/scp fails:**
```bash
# Set VM_USER and VM_HOST explicitly if needed
VM_USER=ubuntu VM_HOST=sharehub.nextdaynet.com bin/migrate-to-vm
```

---

## Step 12: Update OAuth Callback URLs

The Pi used `http://localhost:4000` callback URLs. Production needs HTTPS URLs.

**GitHub:**
1. Go to [github.com/settings/developers](https://github.com/settings/developers)
2. Click your OAuth App
3. Add callback URL: `https://sharehub.nextdaynet.com/auth/github/callback`
4. You can keep the `localhost` URL for Pi development

**LinkedIn:**
1. Go to [linkedin.com/developers/apps](https://www.linkedin.com/developers/apps)
2. Select your app → Auth tab
3. Add redirect URL: `https://sharehub.nextdaynet.com/auth/linkedin/callback`

**Verify:** Sign in via LinkedIn at `https://sharehub.nextdaynet.com` — should work without errors.

---

## Final: End-to-End Verification

```bash
# 1. Service running
sudo systemctl status inventory-locator

# 2. HTTPS responding
curl -I https://sharehub.nextdaynet.com

# 3. WebSocket (LiveView) working — open in browser and interact with the UI
open https://sharehub.nextdaynet.com
```

**Verify in browser:**
1. Sign in with LinkedIn → should redirect correctly and log you in
2. Open an item → modal should load and editing should work
3. Upload a photo → should save and display

---

## Development Workflow on the VM

After the initial deployment, use the VM as your primary development machine.

**SSH tunnel for browser access:**
```bash
ssh -L 4001:localhost:4001 ubuntu@sharehub.nextdaynet.com
```

**Start dev server (in another SSH session):**
```bash
cd ~/inventory-locator-service
mix phx.server --port 4001
```

Open `http://localhost:4001` in your browser — hot reload works as normal.
Port 4001 is not proxied by Nginx so it never touches production traffic.

**Deploy a production update:**
```bash
cd ~/inventory-locator-service
bin/deploy
```

This pulls latest code, rebuilds the release, runs migrations, and restarts the service.

---

## Maintenance

### Viewing Logs

```bash
# Live logs
sudo journalctl -u inventory-locator -f

# Last 100 lines
sudo journalctl -u inventory-locator -n 100
```

### Rollback a Bad Deploy

The `--overwrite` flag in `bin/deploy` replaces the previous release. To roll back:
```bash
git checkout <previous-commit>
bin/deploy
```

### Renewing SSL Certificates

Certbot auto-renews via a systemd timer. To verify:
```bash
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
```

### Database Backups

The built-in backup system writes to `BACKUP_PATH` (`/home/ubuntu/inventory-backups`).

**Manual backup:**
```bash
pg_dump -Fc inventory_locator_prod > ~/inventory-backups/manual_$(date +%Y%m%d).dump
```

**Restore:**
```bash
pg_restore --clean -d inventory_locator_prod ~/inventory-backups/manual_YYYYMMDD.dump
sudo systemctl restart inventory-locator
```

---

## Troubleshooting

### Service Won't Start

```bash
sudo journalctl -u inventory-locator -n 50
```

**Common causes:**
- `DATABASE_URL not set` → Verify `.envrc` has correct values and `direnv allow` was run
- `PHX_HOST not set` → Check `.envrc`
- `port already in use` → Something else on port 4000: `sudo ss -tlnp | grep :4000`
- Release binary missing → Run `MIX_ENV=prod mix release` first

### WebSocket Disconnects

If LiveView connections drop frequently, check the Nginx timeout settings in `deploy/nginx.conf`.
The `proxy_read_timeout 300s` should keep connections alive for 5 minutes of inactivity.

### Photos Not Loading After Migration

`bin/deploy` symlinks `~/inventory-uploads/` and `~/inventory-documents/` into the
release tree after each build. Verify the symlinks exist:
```bash
ls -la _build/prod/rel/inventory_locator/lib/inventory_locator-*/priv/static/uploads
# Should show: uploads -> /home/ubuntu/inventory-uploads
```

If missing, re-run `bin/deploy` — it recreates the symlinks every time.

### SSL Certificate Issues

```bash
sudo certbot certificates  # Check expiry and domains
sudo nginx -t              # Check config syntax
sudo journalctl -u nginx   # Check nginx error logs
```
