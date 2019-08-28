{ pkgs, ... }:
let
  scripts_repo = pkgs.fetchFromGitHub {
    owner = "weechat";
    repo = "scripts";
    rev = "f6f0fd4647024236dd4856a2646c05362078bca4";
    sha256 = "10j0mp5cb0b9cgxhp2wdaidzgc7ir181s3ym74z1pdxkcznha5q3";
  };

  gcautoconnect = pkgs.stdenv.mkDerivation {
    pname = "autoconnect";
    version ="20190524";
    src = scripts_repo;

    passthru.scripts = [ "autoconnect.py" ];
    installPhase = ''
      install -D ./python/autoconnect.py $out/share/autoconnect.py
    '';
  };
in {
  environment.systemPackages = with pkgs; [
    (weechat.override {
      configure = { availablePlugins, ... }: {
        scripts = [ gcautoconnect ] ++ (with pkgs.weechatScripts; [
          weechat-autosort
        ]);
        plugins = [
          (availablePlugins.python.withPackages (ps: [
            (ps.potr.overridePythonAttrs (oldAttrs:
              {
                propagatedBuildInputs = [
                  (ps.buildPythonPackage rec {
                    name = "pycrypto-${version}";
                    version = "2.6.1";

                    src = pkgs.fetchurl {
                      url = "mirror://pypi/p/pycrypto/${name}.tar.gz";
                      sha256 = "0g0ayql5b9mkjam8hym6zyg6bv77lbh66rv1fyvgqb17kfc1xkpj";
                    };

                    patches = pkgs.stdenv.lib.singleton (pkgs.fetchpatch {
                      name = "CVE-2013-7459.patch";
                      url = "https://anonscm.debian.org/cgit/collab-maint/python-crypto.git"
                        + "/plain/debian/patches/CVE-2013-7459.patch?h=debian/2.6.1-7";
                      sha256 = "01r7aghnchc1bpxgdv58qyi2085gh34bxini973xhy3ks7fq3ir9";
                    });

                    buildInputs = [ pkgs.gmp ];

                    preConfigure = ''
                      sed -i 's,/usr/include,/no-such-dir,' configure
                      sed -i "s!,'/usr/include/'!!" setup.py                    '';
                  })
                ];
              }
            ))
          ]))
        ];
      };
    })
    screen
    aspell
    aspellDicts.en
    mosh
  ];
  networking.firewall.allowedUDPPorts = [ 60001 ];
}
