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
        "Darwin_arm64" = "Zc51NNU24CNnTHpWpjQ+w9PefZq+gNWdei4zErLZYXQ=";
        "Darwin_amd64" = "0a7w0l2f5qvh36nghciwr64nxwnikka679qdgnqg88ks5zhy1mv0";
        "Linux_arm64"  = "0p6jjnc3js2507qbhy58ahsjch80b9v5mmql6p1r68ilg51p0xq6";
        "Linux_amd64"  = "0am4dqlh80xscl50vkcww3jsba1ph422xbrm785sl1i6c0k60i7h";
      };
    in 
      builtins.getAttr os_arch_pair sha256_map;

  src = pkgs.fetchurl {
    url  =
      "https://github.com/derailed/k9s/releases/download/v${version}/k9s_${os}_${arch}.tar.gz";
    sha256 = "${sha256}";
  };

  unpackPhase = ":";

  buildPhase = '':'';

  installPhase = ''
    echo "Installing $pname..."
    echo $src
  '';

  meta = with pkgs.stdenv.lib; {
    description = "k9s - Kubernetes Log Viewer";
  };
}
