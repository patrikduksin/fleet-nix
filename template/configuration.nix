{
  imports = [ ./hardware-configuration.nix ]; # nixos-generate-config writes it

  networking.hostName = "CHANGEME";
  nixpkgs.hostPlatform = "x86_64-linux";

  # Anything else this machine needs: packages, Docker, a desktop.

  system.stateVersion = "26.11"; # the release it was installed with; never change it
}
