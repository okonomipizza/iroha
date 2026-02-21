{
  description = "Pipe to AI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    zls = {
      url = "github:zigtools/zls";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        zig-overlay.follows = "zig";
      };
    };
  };

  outputs = {
    self,
    nixpkgs,
    zig,
    zls,
    ...
  }:
    let
      version = nixpkgs.lib.trim (builtins.readFile ./src/.version);
    in
    builtins.foldl' nixpkgs.lib.recursiveUpdate {} (
      builtins.map (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          devShell.${system} = pkgs.callPackage ./nix/devShell.nix {
            zig = zig.packages.${system}."master";
            zls = zls.packages.${system}.zls;
          };

          packages.${system} = let
            mkArgs = optimize: {
              inherit optimize;
              inherit version;

              revision = self.shortRev or self.dirtyShortRev or "dirty";
              zig = zig.packages.${system}."master";
            };
          in rec {
            iroha-debug = pkgs.callPackage ./nix/package.nix (mkArgs "Debug");
            iroha-releasesafe = pkgs.callPackage ./nix/package.nix (mkArgs "ReleaseSafe");
            iroha-releasefast = pkgs.callPackage ./nix/package.nix (mkArgs "ReleaseFast");

            iroha = iroha-releasefast;
            default = iroha;
          };

          formatter.${system} = pkgs.alejandra;
        }
      ) (builtins.attrNames zig.packages)
    );
}
