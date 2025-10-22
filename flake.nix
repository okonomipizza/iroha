{
  description = "Status bar";

  inputs = {
    # nixpkgs.url = "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz";
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
    builtins.foldl' nixpkgs.lib.recursiveUpdate {} (
      builtins.map (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          devShell.${system} = pkgs.callPackage ./nix/devShell.nix {
            zig = zig.packages.${system}."0.15.1";
            zls = zls.packages.${system}.zls;
            inherit system;
          };

          packages.${system} = let
            mkArgs = optimize: {
              inherit optimize;

              revision = self.shortRev or self.dirtyShortRev or "dirty";
              zig = zig.packages.${system}."0.15.1";
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
