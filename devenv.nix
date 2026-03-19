{ pkgs, ... }:

let
  copilotCli = import ./nix/copilot-cli.nix {
    inherit pkgs;
    system = pkgs.system;
  };
in
{
  packages = [ copilotCli ];

  enterShell = ''
    echo "devenv ready:"
    echo "  - copilot      -> run the locally packaged CLI"
    echo "  - buildImage   -> build the Docker image tarball"
    echo "  - loadImage    -> load ./result into Docker"
    echo "  - runImage     -> run the image against the current directory"
  '';

  enterTest = ''
    copilot --version >/dev/null
  '';

  scripts.buildImage.exec = "nix build .#dockerImage";
  scripts.loadImage.exec = "docker load < result";
  scripts.runImage.exec = ''
    docker run --rm -it \
      -v "$PWD:/workspace" \
      -w /workspace \
      -v copilot-state:/var/lib/copilot \
      copilot-cli:latest
  '';
}
