{
  description = "A fleet machine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # A direct input, so the update jobs' `nix flake update` moves it (T3 Code,
    # Claude Code, Codex). Through fleet alone it would stay at fleet-nix's lock.
    agents-nix = {
      url = "github:patrikduksin/agents-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fleet = {
      url = "github:patrikduksin/fleet-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.agents-nix.follows = "agents-nix";
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
