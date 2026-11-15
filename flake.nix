{
  description = "niffler - precompiled Rust NIF distribution for Gleam packages";

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    devenv.url = "github:cachix/devenv";
  };

  outputs =
    {
      self,
      nixpkgs,
      devenv,
    }@inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
      version = (builtins.fromTOML (builtins.readFile ./gleam.toml)).version;
    in
    {
      devShells = forAllSystems (
        system: pkgs: {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [
              # Flakes evaluate purely by default, where PWD is not available.
              # Use --impure for the real working directory; the fallback lets
              # `nix flake check` evaluate the shell without failing.
              ({ lib, ... }: {
                devenv.root = lib.mkForce (
                  let
                    pwd = builtins.getEnv "PWD";
                  in
                  if pwd != "" then pwd else "/tmp/niffler-devenv"
                );
              })
              ./devenv.nix
            ];
          };
        }
      );

      packages = forAllSystems (
        system: pkgs:
        let
          niffler = pkgs.callPackage ./nix/niffler.nix {
            src = self;
            inherit version;
          };
        in
        {
          inherit niffler;
          default = niffler;
        }
      );

      apps = forAllSystems (
        system: pkgs: {
          default = {
            type = "app";
            program = "${self.packages.${system}.niffler}/bin/niffler";
          };
        }
      );

      checks = forAllSystems (
        system: pkgs: {
          niffler = self.packages.${system}.niffler;
        }
      );

      formatter = forAllSystems (system: pkgs: pkgs.nixfmt);
    };
}
