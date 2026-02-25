{ pkgs }:

let
  version = "1.9.1";

  sources = {
    x86_64-linux = {
      url = "https://github.com/AppImage/appimagetool/releases/download/${version}/appimagetool-x86_64.AppImage";
      sha256 = "ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0";
    };
    aarch64-linux = {
      url = "https://github.com/AppImage/appimagetool/releases/download/${version}/appimagetool-aarch64.AppImage";
      sha256 = "f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158";
    };
  };

  src = sources.${pkgs.stdenv.hostPlatform.system}
    or (throw "appimagetool: unsupported system ${pkgs.stdenv.hostPlatform.system}");
in

pkgs.stdenv.mkDerivation {
  pname = "appimagetool";
  inherit version;

  src = pkgs.fetchurl {
    inherit (src) url sha256;
  };

  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/appimagetool
    chmod +x $out/bin/appimagetool
  '';
}
