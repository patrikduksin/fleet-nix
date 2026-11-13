# fleet-nix

The NixOS base every one of my machines imports, and one MCP for all of them:
a hosted agent (the Grok connector at grok.com) signs in to the hub's T3 Code
and through it starts, messages and stops threads on every machine.

Each machine keeps its own repo for what is specific to it (hardware, project
tooling) and imports `fleet.nixosModules.default`.

## What every machine gets

- **Base** (`modules/base.nix`): user `patrik` with my SSH keys (also root),
  passwordless sudo, SSH by key only, Tailscale kept up, mosh, flakes, weekly GC.
  **Nothing is public**: SSH and every service answer on the tailnet only (no
  ping, no mDNS); the one open port is Tailscale's own WireGuard (UDP 41641).
  `fleet.publicSsh = true` opens SSH on 22 for a machine that needs it. With
  SSH tailnet-only, a machine whose Tailscale is down is reached through the
  provider's rescue console.
- **T3 Code** (`modules/t3.nix`): nightly, as a user service, on tailnet HTTPS
  at `https://<host>.<tailnet>:8443`, with linked environments on.
- **Updates** (`modules/updates.nix`): every input (nixpkgs, this repo,
  agents-nix: T3 Code, Claude Code, Codex) is updated and switched to every 2
  hours, and updated with a reboot at 06:00 and 14:00 Santiago time. A push here
  reaches every machine within 2 hours. A failed build changes nothing; a failed
  reboot build reboots into the current generation.
  Logs: `journalctl -u fleet-update-switch`, `journalctl -u fleet-update-reboot -b -1`.

## One MCP for the fleet

- The hub (`fleet.hub = true`) is the one machine a hosted agent signs in to.
  Its connector URL is the tailnet one, `https://<hub>.<tailnet>:8443/mcp`, for
  agents that can join the tailnet (the Grok connector can); nothing is public.
  It stays the same across reinstalls as long as the hub keeps its name.
- For an agent that can't reach the tailnet, `fleet.funnel = true` also serves
  the MCP publicly through Tailscale Funnel at
  `https://<hub>.<tailnet>:10000/mcp`. Funnel passes only `/mcp`, OAuth discovery
  (`/.well-known`), `/oauth/mcp`, the sign-in page (`/connect-agent`, its
  `/assets` and icons) and `/api/auth/session` (which tells a stranger "not
  signed in"); everything else is 404 there. The rest of T3 Code, the app
  included, is on the tailnet at `:8443`.
- Approving the connector: its sign-in page opens on the hub and asks for a
  code. Make one on the hub with `t3 auth pairing create --ttl 5m` and pick
  **Full access**. A sign-in lasts 30 days.
- Membership is the Tailscale tag `tag:t3-fleet`. The hub's `t3-fleet-link`
  timer (3 minutes after boot, then every 6 hours) links every tagged machine
  with full access, renews links a week before their 30 days run out, and
  unlinks machines that lose the tag. Run it now on the hub:
  `systemctl --user start t3-fleet-link`; logs: `journalctl --user -u t3-fleet-link`;
  links: `t3 environment list`.
- It mints each machine's pairing code over SSH with the hub's key, which is in
  `fleet.sshKeys`; if the hub is reinstalled, put its new key there.
- The tailnet policy names the tag's owner (`tagOwners`: admins); with
  `fleet.funnel` it must also allow Funnel for the tag (`nodeAttrs`).

## Add a machine

1. Install NixOS, then `nix flake init -t github:patrikduksin/fleet-nix` in
   `/etc/nixos`; set the hostname (twice: `flake.nix` and `configuration.nix`)
   and keep the generated `hardware-configuration.nix`.
2. `nixos-rebuild switch --flake /etc/nixos#<name>`.
3. `sudo tailscale up --hostname <name> --advertise-tags=tag:t3-fleet` and open
   the login link.

Within 6 hours the hub links it; `systemctl --user start t3-fleet-link` on the
hub does it now. Nothing to change on the hub.

## A new hub

Set `fleet.hub = true` on it, put its SSH key into `fleet.sshKeys`, and give
the connector its URL. Unset it on the old hub.
