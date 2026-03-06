# Deployment Security

Security configuration applied to the GCP VM for the shindex.nextdaynet.com deployment.

## Phoenix Bound to Localhost Only

`config/runtime.exs` binds the HTTP server to `127.0.0.1` rather than all interfaces:

```elixir
http: [ip: {127, 0, 0, 1}]
```

Without this, Phoenix listens on every network interface and is directly reachable on port
4000 from the public internet, bypassing nginx entirely. All external traffic must enter
through nginx on 443.

## Host Firewall (ufw)

ufw is active with a default-deny inbound policy. Only the following ports are open:

| Port | Protocol | Purpose |
|------|----------|---------|
| 22   | TCP      | SSH |
| 80   | TCP      | HTTP (nginx redirects to HTTPS) |
| 443  | TCP      | HTTPS |

This blocks the Erlang Port Mapper Daemon (epmd, port 4369) and the Erlang distribution
port from the internet. These are needed for `bin/inventory_locator remote` to work on the
VM itself (SSH in first, then run the command) but must never be publicly reachable — an
attacker with network access to the distribution port and the release cookie could execute
arbitrary code on the VM.

To check firewall status:

```bash
sudo ufw status verbose
```

## SSH

Password authentication is disabled via GCP's cloud-init defaults
(`/etc/ssh/sshd_config.d/60-cloudimg-settings.conf`). Only SSH key authentication works.

## Automatic Security Updates

`unattended-upgrades` is installed and active, configured to apply security patches daily
without manual intervention (`/etc/apt/apt.conf.d/20auto-upgrades`).
