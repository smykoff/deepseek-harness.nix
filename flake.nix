{
  description = "DeepSeek Harness (dsh) for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
      mkDsh = pkgs: pkgs.callPackage ./package.nix {
        nodeRuntime = pkgs.callPackage ./node.nix { };
      };
    in {
      packages = forAll (pkgs: {
        default = mkDsh pkgs;
        dsh = mkDsh pkgs;
      });

      overlays.default = final: prev: {
        dsh = mkDsh final;
      };
    };
}
