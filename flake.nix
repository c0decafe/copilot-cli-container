{
  description = "Lean GitHub Copilot CLI container built with Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
      shellHelpersFor =
        system:
        let
          pkgs = pkgsFor system;
        in
        [
          (pkgs.writeShellScriptBin "buildImage" ''
            set -eu
            exec nix build .#dockerImage "$@"
          '')
          (pkgs.writeShellScriptBin "loadImage" ''
            set -eu
            docker load < result
          '')
          (pkgs.writeShellScriptBin "runImage" ''
            set -eu
            docker run --rm -it \
              -v "$PWD:/workspace" \
              -w /workspace \
              -v copilot-state:/var/lib/copilot \
              copilot-cli:latest "$@"
          '')
        ];
      copilotCliFor =
        system:
        import ./nix/copilot-cli.nix {
          pkgs = pkgsFor system;
          inherit system;
        };
      entrypointFor =
        system:
        let
          pkgs = pkgsFor system;
        in
        pkgs.runCommandCC "copilot-entrypoint" { } ''
          mkdir -p "$out/bin"
          cat > copilot-entrypoint.c <<'EOF'
          #include <stdio.h>
          #include <string.h>
          #include <unistd.h>
          #include <errno.h>

          static int run_default(void) {
            char *argv[] = { "/bin/copilot", NULL };
            execv(argv[0], argv);
            perror("exec /bin/copilot");
            return 127;
          }

          int main(int argc, char **argv) {
            if (argc > 1) {
              execvp(argv[1], argv + 1);
              perror("exec command");
              return errno == ENOENT ? 127 : 126;
            }

            if (isatty(STDIN_FILENO) && isatty(STDOUT_FILENO)) {
              return run_default();
            }

            puts("copilot-cli container is ready.");
            puts("Run it interactively to launch GitHub Copilot CLI:");
            puts("  docker run --rm -it <image>");
            puts("Or pass a command explicitly:");
            puts("  docker run --rm <image> copilot --help");
            return 0;
          }
          EOF
          $CC -O2 -o "$out/bin/copilot-entrypoint" copilot-entrypoint.c
        '';
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          copilotCli = copilotCliFor system;
          entrypoint = entrypointFor system;
          dockerImage = pkgs.dockerTools.buildLayeredImage {
            name = "copilot-cli";
            tag = "latest";
            contents = [
              copilotCli
              entrypoint
              pkgs.cacert
              pkgs.glibc
              pkgs.stdenv.cc.cc.lib
            ];
            extraCommands = ''
              mkdir -p ./etc ./tmp ./workspace ./var/lib/copilot/.cache ./var/lib/copilot/.config
              chmod 1777 ./tmp
              chmod 0777 ./workspace ./var/lib/copilot ./var/lib/copilot/.cache ./var/lib/copilot/.config
              cat > ./etc/passwd <<'EOF'
              copilot:x:1000:1000:GitHub Copilot CLI:/var/lib/copilot:/bin/copilot
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
                "LD_LIBRARY_PATH=/lib"
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
          copilotCli = copilotCliFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [ copilotCli ] ++ shellHelpersFor system;

            shellHook = ''
              echo "nix develop ready:"
              echo "  - copilot      -> run the locally packaged CLI"
              echo "  - buildImage   -> build the Docker image tarball"
              echo "  - loadImage    -> load ./result into Docker"
              echo "  - runImage     -> run the image against the current directory"
            '';
          };
        }
      );
    };
}
