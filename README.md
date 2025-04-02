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
su -$USER
nordpvn login # if its the first time
nordvpn connect
nordvpn set autoconnect on
```

### Oneleet (pkgs/oneleet/oneleet.nix)

```nix
imports = [
  ...
  <location>/pkgs/oneleet/oneleet.nix
  ...
];

environment.systemPackages = with pkgs; [
	...
    dconf
	libsecret
	gnome-keyring
	...
];

services = {
  windowManager.i3 = {
    ...
    extraSessionCommands = ''
        eval $(gnome-keyring-daemon --daemonize)
        export SHH_AUTH_SOCK
    '';
  }

  dbus = {
    enable = true;
    packaged = [ pkgs.dconf ];
  }

  gnome.gnome-keyring.enable = true;
}

programs = {
    dconf.enable = true;
}

ncompass.oneleet.enable = true;
security.pam.services = {
  login.enableGnomeKeyring = true;
  lightdm.enableGnomeKeyring = true;
};

```
