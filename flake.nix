{
  description = "nCompass nix repo with ncompass packages";

  outputs = { ... }: {
    pkgs = {
      k9s = import ./pkgs/k9s;
      runpod_ctl = import ./pkgs/runpod_ctl;
      nordvpn = import ./pkgs/nordvpn;
      oneleet = import ./pkgs/oneleet;
    };
  };
}
