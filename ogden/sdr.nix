{ nodes, pkgs, ... }:
let
  rtlamr = pkgs.callPackage ({ stdenv, buildGoPackage, fetchFromGitHub }:

buildGoPackage rec {
  name = "rtlamr-${version}";
  version = "20180824";

  goPackagePath = "github.com/bemasher/rtlamr";

  src = fetchFromGitHub {
    rev = "d4b98558f8f095bdba509fdc70fa2cc21ab1c4e9";
    owner = "bemasher";
    repo = "rtlamr";
    sha256 = "0csxv27y5gb49mql19n431iwwmfkm9bhcrk3l5kkx53rq5338ggr";
  };

  preFixup = ''
    ${pkgs.tree}/bin/tree .
  '';
  }) {};
in {
  boot.blacklistedKernelModules = [ "dvb_usb_rtl28xxu" ];

  services.prometheus = {
    scrapeConfigs = [
      {
        job_name = "consumption";
        static_configs = [
          { targets = [ "ogden-encrypted:9111" ]; }
        ];
      }
    ];
  };

  systemd.timers = {
    prometheus-meters-exporter = {
      description = "Captures meters data";
      wantedBy = [ "timers.target" ];
      partOf = [ "prometheus-meters-exporter.service" ];
      enable = true;
      timerConfig = {
        OnCalendar = "*:*";
        RandomizedDelaySec = 15;
        Unit = "prometheus-meters-exporter.service";
        Persistent = "yes";
      };
    };
  };
  systemd.services.prometheus-meters-exporter = {
    path = [ pkgs.rtl-sdr pkgs.netcat rtlamr pkgs.kmod pkgs.gawk pkgs.coreutils pkgs.procps pkgs.utillinux ];
    serviceConfig = {
      Type = "oneshot";
      PrivateTmp =  true;
      WorkingDirectory = "/tmp";
    };
      script = ''
        mkdir -pm 0775 /var/lib/prometheus-node-exporter-text-files
        cd /var/lib/prometheus-node-exporter-text-files
        set -euxo pipefail

        ${./rtl.sh} | ${pkgs.moreutils}/bin/sponge meters.prom
        cat meters.prom
      '';

  };

}
