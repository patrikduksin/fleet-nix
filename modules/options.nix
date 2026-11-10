{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.fleet = {
    user = mkOption {
      type = types.str;
      default = "patrik";
      description = "The one login user; T3 Code runs as this user.";
    };

    sshKeys = mkOption {
      type = types.listOf types.str;
      default = [
        # The fleet hub's key, which t3-fleet-link uses to mint pairing codes
        # on the other machines.
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICSxFm0zinAS9uxhTlguuT1u7nvqAlfzZw3vPysaZ4rD"
        # Laptops
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL06BFsEXkBaJeoY9TM0KICt2a7rk2WxEazAZJGM3YRw"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQjMcwoXhio6zK2R3yIGlDBdUHDWzvtBEvb4VXTCwcm"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE0iOIEYecJt7by7sMJ6IuOOFyh0e39LojiY7QdeNGo+"
      ];
      description = "Keys allowed to log in as the user and as root.";
    };

    hub = mkEnableOption ''
      this machine as the fleet hub: the one machine a hosted agent signs in to
      (through fleet.funnel), which links every other machine tagged `fleet.tag`'';

    funnel = mkEnableOption ''
      Tailscale Funnel on `servePort`: T3 Code, and so its /mcp, public at
      https://<host>.<tailnet>:<servePort>. The hub's public MCP for hosted
      agents; the tailnet policy must allow Funnel for `tag`'';

    tag = mkOption {
      type = types.str;
      default = "tag:t3-fleet";
      description = "Tailscale tag that makes a machine a fleet member.";
    };

    access = mkOption {
      type = types.enum [ "read-only" "approval-required" "auto-accept-edits" "auto" "full-access" ];
      default = "full-access";
      description = "What the hub's agents (and so the connector) may do on the other machines.";
    };

    servePort = mkOption {
      type = types.port;
      default = 8443;
      description = "Tailscale HTTPS port T3 Code is served on: https://<host>.<tailnet>:<port>.";
    };

    updates = {
      flake = mkOption {
        type = types.str;
        default = "/etc/nixos";
        description = "The machine's flake, updated and rebuilt in place.";
      };
      rebootAt = mkOption {
        type = types.listOf types.str;
        default = [ "*-*-* 06,14:00:00 America/Santiago" ];
        description = "When to update every input, build the next boot and reboot.";
      };
      switchAt = mkOption {
        type = types.listOf types.str;
        default = [ "*-*-* 00/2:00:00" ];
        description = "When to update every input and switch to it without a reboot.";
      };
    };
  };
}
