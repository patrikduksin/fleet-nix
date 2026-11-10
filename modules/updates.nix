# Every machine follows its inputs (nixpkgs, this fleet, agents-nix: T3 Code,
# Claude Code, Codex) on its own:
#
# - fleet-update-switch (every 2 hours): update every input and switch to it.
#   Services whose config changed restart; T3 Code doesn't (restartIfChanged =
#   false), so agent turns aren't cut off; a new T3 starts on the next reboot.
# - fleet-update-reboot (06:00 and 14:00 Santiago): update every input, make it
#   the next boot and reboot. About 2 minutes down; T3 continues interrupted
#   turns. A failed build reboots into the current generation.
#
# The machine owns its flake.lock. Both jobs share a lock, so they never overlap.
{ config, ... }:
let
  cfg = config.fleet.updates;
  host = config.networking.hostName;
  common = {
    path = [ "/run/current-system/sw" ];
    environment.HOME = "/root";
    restartIfChanged = false;
    serviceConfig.Type = "oneshot";
  };
in
{
  systemd.services.fleet-update-switch = common // {
    description = "Update every input and switch to it";
    startAt = cfg.switchAt;
    script = ''
      exec 9>/run/fleet-update.lock
      flock -n 9 || { echo "another update is running"; exit 0; }
      nix flake update --flake ${cfg.flake}
      timeout 1h nixos-rebuild switch --flake ${cfg.flake}#${host}
    '';
  };

  systemd.services.fleet-update-reboot = common // {
    description = "Update every input, build the next boot and reboot";
    startAt = cfg.rebootAt;
    script = ''
      exec 9>/run/fleet-update.lock
      flock 9
      nix flake update --flake ${cfg.flake} || echo "flake update failed, rebuilding the current lock"
      timeout 1h nixos-rebuild boot --flake ${cfg.flake}#${host} || echo "build failed, rebooting into the current generation"
      systemctl reboot
    '';
  };
}
