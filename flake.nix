{
  description = "nCompass nix repo with ncompass packages";

  outputs = { self, nixpkgs }: {
    pkgs = {
      k9s = import ./pkgs/k9s;
      runpod_ctl = import ./pkgs/runpod_ctl;
    };
  };
}
