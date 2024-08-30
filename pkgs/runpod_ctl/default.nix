{ pkgs }:
pkgs.stdenv.mkDerivation rec {
  pname   = "runpod_ctl";
  version = "1.14.3";

  os = if      pkgs.stdenv.isDarwin then "darwin"
       else if pkgs.stdenv.isLinux  then "linux"
       else throw "Unsupported OS!";
            
  arch = if   pkgs.stdenv.hostPlatform.system == "aarch64-darwin" then "arm64"
         else "amd64";
         
  sha256 = 
    let
      os_arch_pair = "${os}-${arch}";
      sha256_map = {
        "darwin-arm64" = "Zc51NNU24CNnTHpWpjQ+w9PefZq+gNWdei4zErLZYXQ=";
        "darwin-amd64" = "0a7w0l2f5qvh36nghciwr64nxwnikka679qdgnqg88ks5zhy1mv0";
        "linux-arm64"  = "0p6jjnc3js2507qbhy58ahsjch80b9v5mmql6p1r68ilg51p0xq6";
        "linux-amd64"  = "0am4dqlh80xscl50vkcww3jsba1ph422xbrm785sl1i6c0k60i7h";
      };
    in 
      builtins.getAttr os_arch_pair sha256_map;

  src = pkgs.fetchurl {
    url  =
      "https://github.com/runpod/runpodctl/releases/download/v${version}/runpodctl-${os}-${arch}";
    sha256 = "${sha256}";
  };

  unpackPhase = ":";

  buildPhase = '':'';

  installPhase = ''
    echo "Installing $pname..."
    mkdir -p $out/bin
    cp $src $out/bin/runpodctl
    chmod 555 $out/bin/runpodctl
  '';

  meta = with pkgs.stdenv.lib; {
    description = "Runpod CLI controller";
  };
}
