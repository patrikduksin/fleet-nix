# T3 Code server for the fleet user, on the nightly channel, on every machine.
#
# The package comes from agents-nix, whose CI pins each new nightly, so the
# update jobs bring new versions. Don't use `t3 update`, `t3 up` or
# `t3 service install`: they install a second copy under ~/.t3/runtime and write
# a unit that shadows this one.
#
# It listens on all interfaces; the firewall only lets the tailnet in, where it
# is also served on HTTPS (t3-tailscale-serve): https://<host>.<tailnet>:8443.
# iOS refuses plain HTTP, and agents only sign in over HTTPS. With fleet.funnel
# the same address is public, through Tailscale Funnel.
{ config, lib, pkgs, ... }:
let
  cfg = config.fleet;
  port = toString cfg.servePort;
  publicPort = toString cfg.publicPort;
  # What the public MCP needs, as found by loading T3's sign-in page with
  # nothing else reachable: the MCP, OAuth discovery and endpoints, the sign-in
  # page, its static files, and the session probe that page makes (which only
  # answers "not signed in" to a stranger). Everything else is tailnet-only.
  publicPaths = [
    "/mcp"
    "/.well-known"
    "/oauth/mcp"
    "/connect-agent"
    "/api/auth/session"
    "/assets"
    "/favicon.ico"
    "/apple-touch-icon.png"
    "/manifest.webmanifest"
  ];
  funnelOn = p: "(.AllowFunnel // {}) | keys | any(endswith(\":${p}\"))";

  # Linked environments is a Labs setting in T3's own settings.json; T3 keeps
  # the rest of the file, so only this key is set, before each start.
  enableLinks = pkgs.writeShellScript "t3-enable-linked-environments" ''
    set -eu
    f="$HOME/.t3/userdata/settings.json"
    mkdir -p "$(dirname "$f")"
    [ -s "$f" ] || echo '{}' > "$f"
    ${pkgs.jq}/bin/jq '.linkedEnvironmentsEnabled = true' "$f" > "$f.fleet-tmp"
    mv "$f.fleet-tmp" "$f"
  '';
in
{
  environment.systemPackages = [ pkgs.t3code ];

  systemd.user.services.t3code = {
    description = "T3 Code server";
    wantedBy = [ "default.target" ];
    unitConfig = {
      ConditionUser = cfg.user;
      StartLimitIntervalSec = 0; # keep retrying, never give up
    };
    # New versions start on the next reboot, so updates don't cut agent turns
    # off. If a restart does, T3 resumes the turn on startup.
    restartIfChanged = false;
    # No Nix PATH: agents need the user manager's full PATH (claude, codex, git).
    path = lib.mkForce [ ];
    environment = {
      T3CODE_HOME = "%h/.t3";
      T3CODE_HOST = "0.0.0.0";
    };
    serviceConfig = {
      ExecStartPre = [ "${enableLinks}" ];
      ExecStart = "${pkgs.t3code}/bin/t3 serve";
      WorkingDirectory = "%h";
      KillMode = "mixed";
      OOMPolicy = "continue";
      Restart = "always";
      RestartSec = 5;
      CPUWeight = 1000;
      IOWeight = 1000;
      ManagedOOMPreference = "avoid";
    };
  };

  # tailscale serve keeps the mapping in tailscaled's state; this puts it back
  # on a fresh install.
  systemd.services.t3-tailscale-serve = {
    description = "Serve T3 Code on tailnet HTTPS";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    path = [ config.services.tailscale.package pkgs.jq ];
    serviceConfig = {
      Type = "exec"; # don't hold up boot while tailscale is still logging in
      RemainAfterExit = true;
    };
    script = ''
      until tailscale status --json | jq -e '.BackendState == "Running"' >/dev/null; do sleep 5; done
      funnel_on() { tailscale serve status --json | jq -e "$1" >/dev/null; }

      # The whole of T3 Code, on the tailnet only.
      if funnel_on ${lib.escapeShellArg (funnelOn port)}; then tailscale funnel --https=${port} off; fi
      tailscale serve --bg --https=${port} http://127.0.0.1:3773
    '' + (if cfg.funnel then ''

      # The public MCP: only these paths, through Funnel.
      for path in ${lib.escapeShellArgs publicPaths}; do
        tailscale funnel --bg --https=${publicPort} --set-path="$path" "http://127.0.0.1:3773$path"
      done
    '' else ''

      if funnel_on ${lib.escapeShellArg (funnelOn publicPort)}; then tailscale funnel --https=${publicPort} off; fi
    '');
  };
}
