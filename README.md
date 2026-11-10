Note: include these sections in a valid file connect to your /etc/nixos/configuration.nix
### Steps:
1. clone this repo
2. add relevant snippets

### Setting up docker and virtual machine

```nix
users.users.<user> = {
  extraGroups = [ ... "docker"];
};

# Virtual Machine Setup - use virt-manager to run
virtualisation = {
  libvirtd = {
    enable = true;
    qemu.package = pkgs.qemu_kvm;
    # extraConfig = ''
    #   unix_sock_group = "libvirt";
    #   unix_sock_rw_perms = "0770";
    # '';
  };
  docker.enable = true;
};
users.groups.libvirt.members = [ "deetz" ];
```

### NordVPN (pgks/nordvpn/nordvpn.nix)

```nix
nixpkgs.config.allowUnfree = true;
...
imports = [
  ...
  <location>/pkgs/nordvpn/nordvpn.nix
  ...
];
...
ncompass.nordvpn.enable = true;
networking.firewall.checkReversePath = false;
networking.firewall.allowedUDPPorts = [ 1194 ];
networking.firewall.allowedTCPPorts = [ 443 ];
...
users.users.<your-username>.extraGroups = [ ... "nordvpn" ];
users.groups.nordvpn = {};
```

then in termnal run

```bash
nordpvn login # if its the first time
nordvpn connect
nordvpn set autoconnect on
```

### Oneleet (pkgs/oneleet/oneleet.nix)

```nix
nixpkgs.config.allowUnfree = true;
...
imports = [
  ...
  <location>/pkgs/oneleet/oneleet.nix
  ...
];
...
ncompass.oneleet.enable = true;
```

This installs the Oneleet GUI (`oneleet-agent`, with a desktop entry), the
`oneleet-cli` command, and `oneleet-daemon.service`, which runs Oneleet's
daemon as root. `/opt/Oneleet` links to the package because the daemon
expects that path. Oneleet 2.5.0 and later keep the login session in the
daemon, so no gnome-keyring setup is needed.

The installed release is set by `ncompass.oneleet.version` and
`ncompass.oneleet.hash` (defaults: a known-good release). To follow Oneleet's
releases, keep both in a JSON pin file and update it before rebuilding:

```nix
ncompass.oneleet = {
  enable = true;
  inherit (lib.importJSON ./oneleet-pin.json) version hash;
};
```

```bash
oneleet-update ./oneleet-pin.json   # then rebuild
```

`oneleet-update` reads Oneleet's update feed, test-builds a newer release, and
only then rewrites the pin. It never fails: if the feed is unreachable or the
build fails, it prints a warning and keeps the current pin. Oneleet's in-app
updates cannot apply on NixOS (they fail at the download step because the
package is read-only), so the pin is the only way Oneleet gets updated.
