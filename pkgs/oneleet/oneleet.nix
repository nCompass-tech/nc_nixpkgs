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
  updateCommand = pkgs.writeShellApplication {
    name = "oneleet-update";
    runtimeInputs = [
      pkgs.python3
      config.nix.package
    ];
    text = ''
      exec python3 ${./update.py} \
        --nixpkgs ${pkgs.path} \
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
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      cfg.updateCommand
    ];

    # The update script's unit tests run as part of every system build.
    system.checks = [ updateTests ];

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
