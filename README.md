Note: include these sections in a valid file connect to your /etc/nixos/configuration.nix
### Steps:
1. clone this repo
2. add relevant snippets
3. be sure to import relevant files related to snippets

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
  <location>/nordvpn.nix
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
environment.systemPackages = with pkgs; [
	...
	libsecret
	gnome-keyring
	libgnome-keyring
	...
];

ncompass.oneleet.enable = true;

security.pam.services = {
  login.enableGnomeKeyring = true;
  lightdm.enableGnomeKeyring = true;
  gdm.enableGnomeKeyring = true;
  gdm-password.enableGnomeKeyring = true;
};

security.wrappers.gnome-keyring-daemon = {
  owner = "root";
  group = "root";
  capabilities = "cap_ipc_lock=ep";
  source = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon";
};

```
