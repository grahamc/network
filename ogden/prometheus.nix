{ secrets }:
{ nodes, lib, pkgs, ... }:
let
  prometheus-hue-exporter = pkgs.callPackage ({ stdenv, buildGoPackage, fetchFromGitHub }:
    buildGoPackage rec {
      name = "surfboard_hue-${version}";
      version = "v0.2.1";

      goPackagePath = "github.com/mitchellrj/hue_exporter";

    src = fetchFromGitHub {
      rev = version;
      owner = "mitchellrj";
      repo = "hue_exporter";
      sha256 = "03kxmf6h8aa0wyns5q4bm0zi61k6jlhpyim5vn1nj2f9sjyvhs75";
    };
    }) {};

  hueConfig = pkgs.writeText "config.yml" (builtins.toJSON
  {
    inherit (secrets.hue_exporter_opts) ip_address api_key;
      sensors = {
        match_names = true;
        ignore_types = [
          "CLIPGenericStatus"
        ];
      };
    });
in {
  imports = [ ../../prometheus-packet-spot-market-price-exporter/module.nix ];
  networking.extraHosts = ''
    10.10.2.50 elzar
    12.0.0.1 ogden
    10.5.4.50 turner
    '' + (let
        nums = lib.lists.range 1 9;
        name = num: ''
          37.153.215.191 mac${toString num}-host
          37.153.215.191 mac${toString num}-guest
        '';
      in lib.strings.concatMapStrings name nums);

  services.grafana = {
    enable = true;
    addr = "0.0.0.0";
    auth.anonymous.enable = true;
  };

  services.prometheus = {
    enable = true;
    extraFlags = [
      #"--storage.local.retention=${toString (120 * 24)}h"
      "--storage.tsdb.retention.time=120d"
    ];
    globalConfig = {
      scrape_interval = "30s";
    };
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          { targets = [ "ogden-encrypted:9090" ]; }
        ];
      }

      {
        job_name = "surfboard";
        static_configs = [
          { targets = [ "10.5.3.1:9239" ]; }
        ];
      }

      {
        job_name = "unifi";
        static_configs = [
          { targets = [ "10.5.3.1:9130" ]; }
        ];
      }

      {
        job_name = "hue";
        static_configs = [
          { targets = [ "ogden-encrypted:9366" ]; }
        ];
      }

      {
        job_name = "packet-spot-market-price";
        static_configs = [
          { targets = [ "127.0.0.1:9400" ]; }
        ];
      }

      {
        job_name = "weather-berkshires";
        scheme = "https";
        metrics_path = "/weather";
        params = {
          latitude = [ "42.45" ];
          longitude = [ "-73.25" ];
        };
        static_configs = [
          { targets = [ "weather.gsc.io" ]; }
        ];
      }

      {
        job_name = "weather-status";
        scheme = "https";
        static_configs = [
          { targets = [ "weather.gsc.io" ]; }
        ];
      }

      {
        job_name = "node";
        static_configs = [
          { targets = [
            "10.5.3.1:9100"
            "elzar:9100"
            "turner:9100"
              ] ++ (builtins.map
              (nodename: "${nodename}-encrypted:9100")
              (pkgs.lib.filter (name: name != "lord-nibbler" && (!(lib.strings.hasPrefix "mac" name)))
              (builtins.attrNames nodes)))
              ++ (builtins.map (n: "mac${toString n}-host:6010") (lib.lists.range 1 9))
              ++ (builtins.map (n: "mac${toString n}-guest:6010") (lib.lists.range 1 9));
          }
        ];
      }
    ];
  };


  systemd.services.prometheus-hue-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Restart = "always";
      RestartSec = "60s";
      PrivateTmp =  true;
      WorkingDirectory = "/tmp";
      ExecStart = ''
        ${prometheus-hue-exporter}/bin/hue_exporter \
          --listen.address 0.0.0.0:9366 \
          --config.file=${hueConfig}
      '';
    };
  };

  systemd.timers.prometheus-smartmon-exporter = {
      description = "Captures smartmon data";
      wantedBy = [ "timers.target" ];
      partOf = [ "prometheus-smartmon-exporter.service" ];
      enable = true;
      timerConfig = {
        OnCalendar = "*:*";
        Unit = "prometheus-smartmon-exporter.service";
        Persistent = "yes";
      };
  };
  systemd.services.prometheus-smartmon-exporter = {
    path = [ pkgs.bash pkgs.gawk pkgs.smartmontools ];
    serviceConfig = {
      Type = "oneshot";
      PrivateTmp =  true;
      WorkingDirectory = "/tmp";
    };
      script = ''
        mkdir -pm 0775 /var/lib/prometheus-node-exporter-text-files
        cd /var/lib/prometheus-node-exporter-text-files
        set -euxo pipefail
        ${./smartmon.sh} | ${pkgs.moreutils}/bin/sponge smartmon.prom
      '';

  };

  systemd.timers.prometheus-zfs-snapshot-exporter = {
      description = "Captures snapshot data";
      wantedBy = [ "timers.target" ];
      partOf = [ "prometheus-zfs-snapshot-exporter.service" ];
      enable = true;
      timerConfig = {
        OnCalendar = "*:0/3";
        Unit = "prometheus-zfs-snapshot-exporter.service";
        Persistent = "yes";
      };
  };
  systemd.services.prometheus-zfs-snapshot-exporter = {
    path = with pkgs; [ bash gawk gnused moreutils zfs ];
    serviceConfig = {
      Type = "oneshot";
      PrivateTmp =  true;
      WorkingDirectory = "/tmp";
    };
      script = ''
        mkdir -pm 0775 /var/lib/prometheus-node-exporter-text-files
        cd /var/lib/prometheus-node-exporter-text-files
        set -euxo pipefail
        zfs list -Hp -t snapshot -o name,creation \
          | sed -e 's#@.*\s# #' \
          | awk '
              {
                if (last[$1] < $2) {
                  last[$1]=$2
                }
              }
              END {
                for (m in last) {
                  printf "zfs_snapshot_age_seconds{dataset=\"%s\"} %s\n", m, last[m];
                }
              }
            ' \
          | sponge znapzend-snaps.prom
      '';
  };

  systemd.timers.prometheus-hydra-jobs-exporter = {
      description = "Captures hydra job data";
      wantedBy = [ "timers.target" ];
      partOf = [ "prometheus-hydra-jobs-exporter.service" ];
      enable = true;
      timerConfig = {
        OnCalendar = "*:*";
        Unit = "prometheus-hydra-jobs-exporter.service";
        Persistent = "yes";
      };
  };
  systemd.services.prometheus-hydra-jobs-exporter = {
    path = [
      (pkgs.python3.withPackages (p: [ p.beautifulsoup4 p.requests ]))
    ];

    serviceConfig = {
      Type = "oneshot";
      PrivateTmp =  true;
      WorkingDirectory = "/tmp";
    };
      script = ''
        mkdir -pm 0775 /var/lib/prometheus-node-exporter-text-files
        cd /var/lib/prometheus-node-exporter-text-files
        set -euxo pipefail
        python3 ${./hydra-queue-status.py} | ${pkgs.moreutils}/bin/sponge hydra-queue.prom
      '';

  };


  systemd.timers.prometheus-hydra-machines-exporter = {
      description = "Captures hydra machines data";
      wantedBy = [ "timers.target" ];
      partOf = [ "prometheus-hydra-machines-exporter.service" ];
      enable = true;
      timerConfig = {
        OnCalendar = "*:*";
        Unit = "prometheus-hydra-machines-exporter.service";
        Persistent = "yes";
      };
  };
  systemd.services.prometheus-hydra-machines-exporter = {
    path = [
      (pkgs.python3.withPackages (p: [ p.beautifulsoup4 p.requests p.prometheus_client ]))
    ];

    serviceConfig = {
      Type = "oneshot";
      PrivateTmp =  true;
      WorkingDirectory = "/tmp";
    };
      script = ''
        mkdir -pm 0775 /var/lib/prometheus-node-exporter-text-files
        cd /var/lib/prometheus-node-exporter-text-files
        set -euxo pipefail
        python3 ${./hydra-machine-status.py}
      '';

  };

}
