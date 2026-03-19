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
      bundledToolsFor =
        system:
        let
          pkgs = pkgsFor system;
        in
        [
          pkgs.gitMinimal
          pkgs.openssh
          pkgs."docker-client"
          pkgs.curl
          pkgs.jq
          pkgs.procps
          pkgs.iproute2
          pkgs.busybox
        ];
      hostHelpersFor =
        system:
        let
          pkgs = pkgsFor system;
        in
        pkgs.runCommand "copilot-host-helpers" { } ''
          mkdir -p "$out/bin"
          cat > "$out/bin/host-exec" <<'EOF'
          #!/bin/sh
          set -eu
          
          if [ "$#" -eq 0 ]; then
            echo "usage: host-exec <command> [args...]" >&2
            exit 64
          fi
          
          if [ "$(id -u)" -ne 0 ]; then
            echo "host-exec requires root inside the container (for example: --user 0:0)." >&2
            exit 1
          fi
          
          for chroot_bin in /host/usr/sbin/chroot /host/usr/bin/chroot /host/bin/chroot; do
            if [ -x "$chroot_bin" ]; then
              exec "$chroot_bin" /host "$@"
            fi
          done
          
          echo "host-exec requires the host root mounted at /host and a usable chroot binary on the host." >&2
          exit 1
          EOF
          chmod +x "$out/bin/host-exec"
          
          cat > "$out/bin/host-shell" <<'EOF'
          #!/bin/sh
          set -eu
          exec /bin/host-exec /bin/sh "$@"
          EOF
          chmod +x "$out/bin/host-shell"
        '';
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
          #include <errno.h>
          #include <limits.h>
          #include <stdlib.h>
          #include <stdio.h>
          #include <string.h>
          #include <sys/stat.h>
          #include <unistd.h>

          static int ensure_dir(const char *path, mode_t mode) {
            if (path == NULL || path[0] == '\0') {
              return 0;
            }

            if (mkdir(path, mode) == 0 || errno == EEXIST) {
              return 0;
            }

            perror(path);
            return -1;
          }

          static int ensure_runtime_dirs(void) {
            const char *home = getenv("HOME");
            const char *cache = getenv("XDG_CACHE_HOME");
            const char *config = getenv("XDG_CONFIG_HOME");
            char docker_dir[PATH_MAX];
            char ssh_dir[PATH_MAX];

            if (ensure_dir(home, 0755) < 0 || ensure_dir(cache, 0755) < 0 || ensure_dir(config, 0755) < 0) {
              return -1;
            }

            if (home == NULL || home[0] == '\0') {
              return 0;
            }

            if (snprintf(docker_dir, sizeof(docker_dir), "%s/.docker", home) >= (int)sizeof(docker_dir) ||
                snprintf(ssh_dir, sizeof(ssh_dir), "%s/.ssh", home) >= (int)sizeof(ssh_dir)) {
              fputs("HOME path is too long.\n", stderr);
              return -1;
            }

            if (ensure_dir(docker_dir, 0700) < 0 || ensure_dir(ssh_dir, 0700) < 0) {
              return -1;
            }

            return 0;
          }

          static int run_default(void) {
            char *argv[] = { "/bin/copilot", NULL };
            execv(argv[0], argv);
            perror("exec /bin/copilot");
            return 127;
          }

          int main(int argc, char **argv) {
            if (ensure_runtime_dirs() < 0) {
              return 1;
            }

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
          bundledTools = bundledToolsFor system;
          hostHelpers = hostHelpersFor system;
          dockerImage = pkgs.dockerTools.buildLayeredImage {
            name = "copilot-cli";
            tag = "latest";
            contents = [
              copilotCli
              entrypoint
              hostHelpers
            ] ++ bundledTools ++ [
              pkgs.cacert
              pkgs.glibc
              pkgs.stdenv.cc.cc.lib
            ];
            extraCommands = ''
              mkdir -p ./etc ./tmp ./workspace ./var/lib/copilot/.cache ./var/lib/copilot/.config ./var/lib/copilot/.docker ./var/lib/copilot/.ssh
              chmod 1777 ./tmp
              chmod 0777 ./workspace ./var/lib/copilot ./var/lib/copilot/.cache ./var/lib/copilot/.config
              chmod 0700 ./var/lib/copilot/.docker ./var/lib/copilot/.ssh
              cat > ./etc/passwd <<'EOF'
              copilot:x:1000:1000:GitHub Copilot CLI:/var/lib/copilot:/bin/copilot
              EOF
              cat > ./etc/group <<'EOF'
              copilot:x:1000:
              EOF
            '';
            fakeRootCommands = ''
              chown 1000:1000 ./var/lib/copilot ./var/lib/copilot/.cache ./var/lib/copilot/.config ./var/lib/copilot/.docker ./var/lib/copilot/.ssh
            '';
            config = {
              User = "1000:1000";
              WorkingDir = "/workspace";
              Entrypoint = [ "/bin/copilot-entrypoint" ];
              Env = [
                "HOME=/var/lib/copilot"
                "HOST_ROOT=/host"
                "LD_LIBRARY_PATH=/lib"
                "PATH=/bin"
                "SHELL=/bin/sh"
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
