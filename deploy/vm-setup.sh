#!/usr/bin/env bash
# One-time VM setup for inventory-locator-service.
# Run as the ubuntu user on the GCP VM.
set -euo pipefail

APP_DIR="$HOME/inventory-locator-service"

echo "==> Installing PostgreSQL..."
sudo apt-get update
sudo apt-get install -y postgresql postgresql-contrib

echo "==> Creating database user and databases..."
# Creates a superuser matching the ubuntu user so no password is needed for local connections
sudo -u postgres createuser --superuser ubuntu 2>/dev/null || echo "(user already exists)"
createdb inventory_locator_prod 2>/dev/null || echo "(db already exists)"
createdb inventory_locator_dev 2>/dev/null || echo "(db already exists)"

echo "==> Installing asdf..."
if [[ ! -d "$HOME/.asdf" ]]; then
  git clone https://github.com/asdf-vm/asdf.git "$HOME/.asdf" --branch v0.14.0
  echo '. "$HOME/.asdf/asdf.sh"' >> "$HOME/.zshrc"
  echo 'eval "$(direnv hook zsh)"' >> "$HOME/.zshrc"
fi

source "$HOME/.asdf/asdf.sh"

echo "==> Installing Erlang and Elixir build dependencies..."
sudo apt-get install -y \
  build-essential autoconf m4 libncurses5-dev libwxwidgets-dev \
  libgl1-mesa-dev libglu1-mesa-dev libpng-dev libssh-dev unixodbc-dev \
  xsltproc fop libxml2-utils libncurses-dev

echo "==> Installing Erlang/OTP 28.3..."
asdf plugin add erlang 2>/dev/null || true
asdf install erlang 28.3

echo "==> Installing Elixir 1.19.4-otp-28..."
asdf plugin add elixir 2>/dev/null || true
asdf install elixir 1.19.4-otp-28

echo "==> Cloning repository..."
mkdir -p "$(dirname "$APP_DIR")"
git clone git@github.com:greghgradwell/inventory-locator-service.git "$APP_DIR"
cd "$APP_DIR"

echo "==> Installing Hex and Rebar..."
mix local.hex --force
mix local.rebar --force

echo "==> Configuring environment..."
echo ""
echo "  Next: copy deploy/.envrc.example to .envrc and fill in real values."
echo "  Generate SECRET_KEY_BASE with: mix phx.gen.secret"
echo ""
echo "  cp deploy/.envrc.example .envrc && nano .envrc"

echo "==> Installing systemd service..."
sudo cp deploy/inventory-locator.service /etc/systemd/system/
sudo sed -i "s|/home/ubuntu/inventory-locator-service|$APP_DIR|g" /etc/systemd/system/inventory-locator.service
sudo systemctl daemon-reload
sudo systemctl enable inventory-locator

echo "==> Installing Nginx config..."
sudo cp deploy/nginx.conf /etc/nginx/sites-available/sharehub.nextdaynet.com
sudo ln -sf /etc/nginx/sites-available/sharehub.nextdaynet.com /etc/nginx/sites-enabled/sharehub.nextdaynet.com

echo "==> Requesting SSL certificate..."
sudo certbot --nginx -d sharehub.nextdaynet.com

sudo nginx -t && sudo systemctl reload nginx

echo ""
echo "==> Setup complete. Now:"
echo "  1. Fill in .envrc with real values"
echo "  2. Run: bin/deploy"
echo "  3. To migrate data from Pi, run on the Pi: bin/migrate-to-vm"
