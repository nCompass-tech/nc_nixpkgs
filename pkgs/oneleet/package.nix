{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  glib,
  gtk3,
  libsecret,
  nss,
  nspr,
  at-spi2-atk,
  cups,
  dbus,
  libdrm,
  libxkbcommon,
  mesa,
  pango,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  # The release to build and the SRI hash of its .deb (sha512 from Oneleet's
  # update feed). oneleet-update test-builds this file with candidate values.
  version,
  hash,
}:

stdenv.mkDerivation {
  pname = "oneleet";
  inherit version;

  src = fetchurl {
    url = "https://downloads.oneleet.com/agent/linux/Oneleet_${version}_amd64.deb";
    inherit hash;
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    glib
    gtk3
    libsecret
    nss
    nspr
    at-spi2-atk
    cups
    dbus
    libdrm
    libxkbcommon
    mesa
    pango
    stdenv.cc.cc
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
  ];

  # The .deb marks chrome-sandbox setuid root, which the Nix build sandbox
  # refuses to create; extract without restoring owner or setuid/setgid bits.
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile "$src" | tar -x --no-same-owner --no-same-permissions --mode=a-s
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/opt
    cp -R usr/* $out/
    cp -R opt/* $out/opt/

    substituteInPlace $out/share/applications/oneleet-agent.desktop \
      --replace-fail "/opt/Oneleet/oneleet-agent" "$out/bin/oneleet-agent"

    makeWrapper $out/opt/Oneleet/oneleet-agent $out/bin/oneleet-agent \
      --add-flags "--password-store=gnome-libsecret"

    # Oneleet's install script links the daemon binary as oneleet-cli.
    ln -s $out/opt/Oneleet/oneleet-daemon $out/bin/oneleet-cli

    runHook postInstall
  '';

  meta = {
    description = "Oneleet device-monitoring agent (GUI, daemon and osquery)";
    homepage = "https://oneleet.com";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "oneleet-agent";
  };
}
