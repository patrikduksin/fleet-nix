# What every machine is: one user, SSH by key, reachable over the tailnet.
{ config, lib, ... }:
let
  cfg = config.fleet;
in
{
  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  users.users.${cfg.user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = cfg.sshKeys;
    linger = true; # user services (T3 Code) run without a login
  };
  users.users.root.openssh.authorizedKeys.keys = cfg.sshKeys;
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    openFirewall = cfg.publicSsh; # tailnet-only otherwise (tailscale0 is trusted)
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Nothing is public but Tailscale's own WireGuard port (UDP 41641, for direct
  # peer connections) and, on the hub, the MCP through Funnel (which arrives over
  # Tailscale too). SSH and every service are tailnet-only unless fleet.publicSsh.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = lib.optional cfg.publicSsh 22;
    allowPing = false;
    trustedInterfaces = [ "tailscale0" ];
  };
  # mDNS (UDP 5353) is for finding devices on a local network; a server has
  # none. Avahi may still run (Sunshine turns it on), just not open to the world.
  services.avahi.openFirewall = lib.mkDefault false;
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
  # The tailnet is the way in, so keep tailscaled up no matter how it exits.
  systemd.services.tailscaled = {
    startLimitIntervalSec = 0;
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = 5;
    };
  };

  programs.mosh = {
    enable = true;
    openFirewall = false;
  };

  zramSwap.enable = lib.mkDefault true;

  nixpkgs.config.allowUnfree = true;
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" cfg.user ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 3d";
    };
  };
}
