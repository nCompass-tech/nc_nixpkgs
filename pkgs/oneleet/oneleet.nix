{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.ncompass.oneleet;

  # Moves a pin file ({ "version", "hash" }) to the newest release in Oneleet's
  # update feed, after test-building it against this system's nixpkgs. It
  # never fails a rebuild: every problem is a warning and exit status 0.
  # Callers can pass their own --nixpkgs/--package after these defaults (the
  # last value wins), e.g. the nixpkgs their next switch will use.
  #
  # builtins.path names nixpkgs "source", which resolves to the store path the
  # system already has; interpolating pkgs.path directly would copy all of
  # nixpkgs (~200 MB) into a second store path per nixpkgs revision.
  nixpkgsSource = builtins.path {
    inherit (pkgs) path;
    name = "source";
  };

  updateCommand = pkgs.writeShellApplication {
    name = "oneleet-update";
    runtimeInputs = [
      pkgs.python3
      config.nix.package
    ];
    text = ''
      exec python3 ${./update.py} \
        --nixpkgs ${nixpkgsSource} \
        --package ${./package.nix} \
        --app-update-yml ${cfg.package}/opt/Oneleet/resources/app-update.yml \
        "$@"
    '';
  };

  updateTests = pkgs.runCommand "oneleet-update-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    cp ${./update.py} update.py
    cp ${./test_update.py} test_update.py
    python3 -m unittest -v test_update
    touch $out
  '';

  # Logging in from the Oneleet window runs `pkexec oneleet-daemon login`,
  # which needs the setuid pkexec wrapper. NixOS leaves that wrapper off
  # (security.polkit.enablePkexecWrapper defaults to false), so the window
  # fails with a generic "Connection Failed". This command does the same login
  # through sudo instead: the token goes to the daemon CLI in a private file
  # (deleted after reading), never on the command line, and the CLI asks for
  # the workspace confirmation in the terminal.
  loginCommand = pkgs.writeShellApplication {
    name = "oneleet-login";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      pause() {
        printf '\nPress Enter to close this window.'
        read -r _ || true
      }

      printf 'Connect this device to Oneleet.\n'
      printf 'Paste the connect token from the Oneleet portal (input hidden): '
      IFS= read -rs token || true
      echo
      if [ -z "$token" ]; then
        echo "No token entered; nothing was done."
        pause
        exit 1
      fi

      dir=$(mktemp -d)
      trap 'rm -rf "$dir"' EXIT
      (umask 077 && printf '%s' "$token" >"$dir/token")
      unset token

      echo "Running sudo oneleet-cli login: it asks for your password, then to confirm the workspace."
      status=0
      sudo ${cfg.package}/bin/oneleet-cli login --enrollment-token-file "$dir/token" || status=$?
      if [ "$status" -eq 0 ]; then
        echo "Done: this device is connected to Oneleet."
      else
        echo "Login failed (exit status $status)."
      fi
      pause
      exit "$status"
    '';
  };

  loginDesktopItem = pkgs.makeDesktopItem {
    name = "oneleet-login";
    desktopName = "Oneleet login";
    comment = "Connect this device to Oneleet with a token from the portal";
    exec = "${loginCommand}/bin/oneleet-login";
    icon = "oneleet-agent";
    terminal = true;
    categories = [ "Utility" ];
  };

  loginTests = pkgs.runCommand "oneleet-login-tests" { } ''
    bash ${./test_login.sh} ${loginCommand}/bin/oneleet-login
    touch $out
  '';
in
{
  options.ncompass.oneleet = {
    enable = mkEnableOption "the Oneleet agent (GUI, root daemon and osquery)";

    version = mkOption {
      type = types.str;
      default = "2.5.0";
      description = ''
        Oneleet release to install. Set together with `hash`, typically from
        a pin file that `oneleet-update <pin-file>` keeps current.
      '';
    };

    hash = mkOption {
      type = types.str;
      default = "sha512-0+cSZfVZ9U2JbFzZtKQzjHOgwCEhRws7VtDCrLBSPjk5/lwQDTe8d6SzLBSRVixdMGO6BWrlL5QBXbJ+aNnw6Q==";
      description = ''
        SRI hash of `Oneleet_<version>_amd64.deb`: the sha512 from Oneleet's
        update feed, prefixed with `sha512-`.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { inherit (cfg) version hash; };
      defaultText = literalExpression "pkgs.callPackage ./package.nix { inherit (cfg) version hash; }";
      description = "The Oneleet package.";
    };

    updateCommand = mkOption {
      type = types.package;
      default = updateCommand;
      readOnly = true;
      internal = true;
      description = "The oneleet-update command, exposed so it can be built on its own.";
    };

    loginCommand = mkOption {
      type = types.package;
      default = loginCommand;
      readOnly = true;
      internal = true;
      description = "The oneleet-login command, exposed so it can be built on its own.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      cfg.updateCommand
      cfg.loginCommand
      loginDesktopItem
    ];

    # The update and login scripts' tests run as part of every system build.
    system.checks = [
      updateTests
      loginTests
    ];

    # Oneleet's own .deb install script registers this unit with
    # `oneleet-daemon install`; NixOS never runs that script, so the unit is
    # declared here with the same settings. Deliberate choices:
    # - ExecStart must run the daemon from the read-only Nix store, never from a
    #   writable copy. The daemon downloads its self-updates next to its own
    #   executable; the read-only store makes that download fail before it
    #   quits the GUI or stops this service, so only Nix ever updates Oneleet.
    # - No PrivateTmp: the GUI reaches the daemon at /tmp/oneleet-daemon.sock.
    # - Full root and no confinement, as on Ubuntu: Oneleet inspects the whole
    #   machine, and an allowlist here would fall behind a daemon that updates
    #   on every rebuild. The daemon creates /etc/oneleet, /var/lib/oneleet,
    #   /var/log/oneleet and /var/opt/Oneleet itself.
    systemd.services.oneleet-daemon = {
      description = "Oneleet Agent daemon";
      wantedBy = [ "multi-user.target" ];
      # Ordering only. Wanting network-online.target would pull in the
      # wait-online service and hold up multi-user.target on offline boots;
      # the daemon retries on its own (Restart=always).
      after = [ "network-online.target" ];
      unitConfig = {
        StartLimitIntervalSec = 5;
        StartLimitBurst = 10;
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/opt/Oneleet/oneleet-daemon";
        Restart = "always";
        RestartSec = 120;
      };
    };

    # The daemon has hard-coded /opt/Oneleet/... paths; point them at the
    # package. The link is read-only like the store behind it.
    systemd.tmpfiles.rules = [
      "d /opt 0755 root root - -"
      "L+ /opt/Oneleet - - - - ${cfg.package}/opt/Oneleet"
    ];
  };
}
