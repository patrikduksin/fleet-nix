{
  description = "patrik's machine fleet: shared NixOS base, T3 Code, one MCP for every machine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # T3 Code nightly, Claude Code and Codex from official release binaries;
    # CI there bumps the pins hourly. Its overlay replaces nixpkgs' claude-code
    # and codex (days behind).
    agents-nix = {
      url = "github:patrikduksin/agents-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { agents-nix, ... }: {
    # Import this in a machine's flake; see template/ and README.md.
    nixosModules.default = {
      imports = [
        ./modules/options.nix
        ./modules/base.nix
        ./modules/updates.nix
        ./modules/t3.nix
        ./modules/fleet-link.nix
      ];
      nixpkgs.overlays = [ agents-nix.overlays.default ];
    };

    templates.default = {
      path = ./template;
      description = "A new fleet machine";
    };
  };
}
