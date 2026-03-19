{
  description = "Lean GitHub Copilot CLI container built with Nix and devenv";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
  };

  nixConfig = {
    extra-substituters = [ "https://devenv.cachix.org" ];
    extra-trusted-public-keys = [
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    ];
  };

  outputs = inputs@{ self, nixpkgs, devenv, ... }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
      copilotCliFor =
        system:
        import ./nix/copilot-cli.nix {
          pkgs = pkgsFor system;
          inherit system;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          copilotCli = copilotCliFor system;
          entrypoint = pkgs.writeShellScriptBin "copilot-entrypoint" (builtins.readFile ./scripts/entrypoint.sh);
          dockerImage = pkgs.dockerTools.buildLayeredImage {
            name = "copilot-cli";
            tag = "latest";
            contents = [
              copilotCli
              entrypoint
              pkgs.cacert
              pkgs.dockerTools.binSh
              pkgs.glibc
              pkgs.stdenv.cc.cc.lib
            ];
            extraCommands = ''
              ln -sfn lib ./lib64
              mkdir -p ./etc ./tmp ./workspace ./var/lib/copilot/.cache ./var/lib/copilot/.config
              chmod 1777 ./tmp
              chmod 0777 ./workspace ./var/lib/copilot ./var/lib/copilot/.cache ./var/lib/copilot/.config
              cat > ./etc/passwd <<'EOF'
              copilot:x:1000:1000:GitHub Copilot CLI:/var/lib/copilot:/bin/sh
              EOF
              cat > ./etc/group <<'EOF'
              copilot:x:1000:
              EOF
            '';
            config = {
              User = "1000:1000";
              WorkingDir = "/workspace";
              Entrypoint = [ "/bin/copilot-entrypoint" ];
              Env = [
                "HOME=/var/lib/copilot"
                "LD_LIBRARY_PATH=/lib:/lib64"
                "PATH=/bin"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "XDG_CACHE_HOME=/var/lib/copilot/.cache"
                "XDG_CONFIG_HOME=/var/lib/copilot/.config"
              ];
              Volumes = {
                "/var/lib/copilot" = { };
              };
            };
          };
        in
        rec {
          inherit copilotCli dockerImage;
          default = dockerImage;
        }
      );

      apps = forAllSystems (
        system:
        let
          copilotCli = copilotCliFor system;
        in
        {
          default = {
            type = "app";
            program = "${copilotCli}/bin/copilot";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [ ./devenv.nix ];
          };
        }
      );
    };
}
