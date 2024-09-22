{ pkgs }:
pkgs.stdenv.mkDerivation rec {
  pname   = "k9s";
  version = "0.32.5";

  os = if      pkgs.stdenv.isDarwin then "Darwin"
       else if pkgs.stdenv.isLinux  then "Linux"
       else throw "Unsupported OS!";
            
  arch = if   pkgs.stdenv.hostPlatform.system == "aarch64-darwin" then "arm64"
         else "amd64";
         
  sha256 = 
    let
      os_arch_pair = "${os}_${arch}";
      sha256_map = {
        "Darwin_arm64" = "0zgid60p3vcvi251sx75j05rxfh1hbczm7253cd82j0civ652sli";
        "Darwin_amd64" = "0000000000000000000000000000000000000000000000000000";
        "Linux_arm64"  = "0000000000000000000000000000000000000000000000000000";
        "Linux_amd64"  = "18yf4vr4pgdl5ssijmpf45amdasjrd3mbgnsp1cjnadszvsiphrk";
      };
    in 
      builtins.getAttr os_arch_pair sha256_map;

  src = pkgs.fetchurl {
    url  =
      "https://github.com/derailed/k9s/releases/download/v${version}/k9s_${os}_${arch}.tar.gz";
    sha256 = "${sha256}";
  };
  
  unpackPhase = ''
    tar -xvf $src
  '';
  
  buildPhase = ''
  '';
  
  installPhase = ''
    echo "Installing $pname..."
    mkdir -p $out/bin
    cp k9s $out/bin/
    chmod 555 $out/bin/k9s
    echo "$pname binary installed at " $out/bin/k9s
  '';

  meta = with pkgs.stdenv.lib; {
    description = "k9s - Kubernetes Log Viewer";
  };
}
