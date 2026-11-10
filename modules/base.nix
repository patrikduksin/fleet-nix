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
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Public: SSH and Tailscale only; everything else over the tailnet.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "tailscale0" ];
  };
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
