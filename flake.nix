{
  description = "nCompass nix repo with ncompass packages";

  outputs = { self, nixpkgs }: {
    pkgs = {
      runpod_ctl = import ./pkgs/runpod_ctl;
    };
  };
}
