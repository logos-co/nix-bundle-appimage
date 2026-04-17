{ pkgs }:

{ drv
, name ? drv.pname or drv.name or "AppImage"
, bundle
, desktopFile
, icon
}:

let
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

  nativeBuildInputs = [ pkgs.file pkgs.squashfsTools ];

  buildPhase = ''
    # Construct AppDir
    mkdir -p AppDir/usr/bin AppDir/usr/lib

    # Copy bundle contents into usr/
    cp -a ${bundle}/bin/. AppDir/usr/bin/
    if [ -d "${bundle}/lib" ]; then
      cp -a ${bundle}/lib/. AppDir/usr/lib/
    fi

    # Copy any extra dirs from the bundle (e.g., plugins, modules)
    for dir in ${bundle}/*/; do
      dirname=$(basename "$dir")
      if [ "$dirname" != "bin" ] && [ "$dirname" != "lib" ]; then
        cp -a "$dir" "AppDir/usr/$dirname"
      fi
    done

    # Install .desktop file at AppDir root
    cp ${desktopFile} AppDir/${name}.desktop

    # Patch Exec= to just the binary name (AppImage convention)
    sed -i "s|^Exec=.*|Exec=${execBasename}|" AppDir/${name}.desktop

    # Install icon at AppDir root (file manager thumbnail)
    cp ${icon} AppDir/${name}.${iconExt}
    ln -s ${name}.${iconExt} AppDir/.DirIcon

    # Install icon in FreeDesktop standard path (taskbar/window icon)
    mkdir -p AppDir/usr/share/icons/hicolor/256x256/apps
    cp ${icon} AppDir/usr/share/icons/hicolor/256x256/apps/${name}.${iconExt}

    # Patch Icon= field in .desktop to match installed icon name
    sed -i "s|^Icon=.*|Icon=${name}|" AppDir/${name}.desktop

    # Create AppRun
    cat > AppDir/AppRun <<'EOF'
#!/bin/sh
set -e
APPDIR="$(dirname "$(readlink -f "$0")")"
export PATH="$APPDIR/usr/bin:$PATH"
export LD_LIBRARY_PATH="$APPDIR/usr/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$APPDIR/usr/bin/${execBasename}" "$@"
EOF
    chmod +x AppDir/AppRun

    # Build AppImage: create uncompressed squashfs, then concatenate with runtime.
    # The AppImage runtime FUSE-mounts the squashfs and reads blocks on every
    # page fault during app startup. Any compressor (gzip, zstd, etc.) means
    # every dlopen of a Qt library or plugin pays CPU decompression cost on the
    # cold launch, which adds up to minutes for large Qt apps. Disabling all
    # four compression layers (-noI inode, -noD data, -noF fragment, -noX xattr)
    # trades AppImage size for near-native launch performance.
    mksquashfs AppDir appimage.squashfs -root-owned -noappend \
      -noI -noD -noF -noX
    cat ${appimageRuntime} appimage.squashfs > ${name}.AppImage
    chmod +x ${name}.AppImage
  '';

  installPhase = ''
    mkdir -p $out
    cp ${name}.AppImage $out/
  '';
}
