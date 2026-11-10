{
  description = "A fleet machine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    fleet = {
      url = "github:patrikduksin/fleet-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, fleet, ... }: {
    # The name must match networking.hostName: the update jobs build #<hostName>.
    nixosConfigurations.CHANGEME = nixpkgs.lib.nixosSystem {
      modules = [
        fleet.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
