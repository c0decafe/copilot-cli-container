{ pkgs, system }:

let
  inherit (pkgs) fetchurl lib stdenvNoCC;

  version = "1.0.8";

  assets = {
    x86_64-linux = {
      file = "copilot-linux-x64.tar.gz";
      hash = "sha256-lIqjsoL0I4fHWfvtbYSF4SzTMAzlYUc7SK+Yi45TBrM=";
    };
    aarch64-linux = {
      file = "copilot-linux-arm64.tar.gz";
      hash = "sha256-zq+D2KDZiMH8zeMe3XY9L+XPkhy+emrrTeSsl0DvG1I=";
    };
  };

  asset =
    assets.${system} or (throw "Unsupported system for copilot-cli: ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "copilot-cli";
  inherit version;

  src = fetchurl {
    url = "https://github.com/github/copilot-cli/releases/download/v${version}/${asset.file}";
    hash = asset.hash;
  };

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;
  dontPatchELF = true;
  dontStrip = true;

  unpackPhase = ''
    tar -xzf "$src"
  '';

  installPhase = ''
    install -Dm755 copilot "$out/bin/copilot"
  '';

  meta = {
    description = "GitHub Copilot CLI";
    homepage = "https://github.com/github/copilot-cli";
    license = lib.licenses.mit;
    mainProgram = "copilot";
    platforms = builtins.attrNames assets;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
