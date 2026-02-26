{ pkgs }:

{ drv
, name ? drv.pname or drv.name or "AppImage"
, bundle
, desktopFile
, icon
}:

let
  appimagetool = import ./fetchAppImageTool.nix { inherit pkgs; };
  appimageRuntime = import ./fetchAppImageRuntime.nix { inherit pkgs; };

  # Extract the Exec= binary name from the .desktop file.
  desktopContent = builtins.readFile desktopFile;
  execLine = builtins.head (
    builtins.filter
      (line: builtins.match "Exec=.*" line != null)
      (pkgs.lib.splitString "\n" desktopContent)
  );
  execCmd = builtins.head (
    pkgs.lib.splitString " " (builtins.replaceStrings ["Exec="] [""] execLine)
  );
  execBasename = builtins.baseNameOf execCmd;

  # Determine icon file extension from the path
  iconPath = builtins.toString icon;
  iconExt = pkgs.lib.last (pkgs.lib.splitString "." iconPath);
in

pkgs.stdenv.mkDerivation {
  pname = "${name}-appimage";
  version = drv.version or "0";

  src = null;
  dontUnpack = true;
  dontFixup = true;

  nativeBuildInputs = [ pkgs.file ];

  buildPhase = ''
    # Construct AppDir
    mkdir -p AppDir/usr/bin AppDir/usr/lib

    # Copy bundle contents into usr/
    cp -a ${bundle}/bin/. AppDir/usr/bin/
    if [ -d "${bundle}/lib" ]; then
      cp -a ${bundle}/lib/. AppDir/usr/lib/
    fi

    # Copy any extra dirs from the bundle (e.g., share/glib-2.0/schemas)
    for dir in ${bundle}/*/; do
      dirname=$(basename "$dir")
      if [ "$dirname" != "bin" ] && [ "$dirname" != "lib" ]; then
        mkdir -p "AppDir/usr/$dirname"
        cp -a "$dir"/. "AppDir/usr/$dirname/"
        chmod -R u+w "AppDir/usr/$dirname"
      fi
    done

    # Merge share directory from the original derivation (icons, .desktop, etc.)
    if [ -d "${drv}/share" ]; then
      mkdir -p AppDir/usr/share
      cp -an ${drv}/share/. AppDir/usr/share/ 2>/dev/null || true
      chmod -R u+w AppDir/usr/share
    fi

    # Install .desktop file at AppDir root
    cp ${desktopFile} AppDir/${name}.desktop

    # Patch Exec= to just the binary name (AppImage convention)
    sed -i "s|^Exec=.*|Exec=${execBasename}|" AppDir/${name}.desktop

    # Install icon at AppDir root (file manager thumbnail)
    cp ${icon} AppDir/${name}.${iconExt}
    ln -s ${name}.${iconExt} AppDir/.DirIcon

    # Install icon in FreeDesktop standard path (taskbar/window icon).
    # Use pixmaps/ which accepts any size, avoiding hicolor size-matching issues.
    mkdir -p AppDir/usr/share/pixmaps
    cp ${icon} AppDir/usr/share/pixmaps/${name}.${iconExt}

    # Patch Icon= field in .desktop to match installed icon name
    sed -i "s|^Icon=.*|Icon=${name}|" AppDir/${name}.desktop

    # Create AppRun
    cat > AppDir/AppRun <<'EOF'
#!/bin/sh
set -e
APPDIR="$(dirname "$(readlink -f "$0")")"
export PATH="$APPDIR/usr/bin:$PATH"
export LD_LIBRARY_PATH="$APPDIR/usr/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="$APPDIR/usr/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
export GSETTINGS_SCHEMA_DIR="$APPDIR/usr/share/glib-2.0/schemas''${GSETTINGS_SCHEMA_DIR:+:$GSETTINGS_SCHEMA_DIR}"
exec "$APPDIR/usr/bin/${execBasename}" "$@"
EOF
    chmod +x AppDir/AppRun

    # Build AppImage
    ARCH=$(uname -m) ${appimagetool}/bin/appimagetool --appimage-extract-and-run --runtime-file ${appimageRuntime} AppDir ${name}.AppImage
  '';

  installPhase = ''
    mkdir -p $out
    cp ${name}.AppImage $out/
  '';
}
