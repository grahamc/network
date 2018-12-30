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
    inherit (secrets.hue) ip_address api_key;
      sensors = {
        match_names = true;
        ignore_types = [
          "CLIPGenericStatus"
        ];
      };
    });
in {
  networking.extraHosts = ''
    12.0.0.1 ogden
    147.75.198.47 packet-epyc-1
    147.75.98.145 packet-t2-4
    147.75.65.54  packet-t2a-1
    147.75.79.198 packet-t2a-2
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
          { targets = [ "lord-nibbler-unencrypted:9239" ]; }
        ];
      }

      {
        job_name = "unifi";
        static_configs = [
          { targets = [ "lord-nibbler-unencrypted:9130" ]; }
        ];
      }

      {
        job_name = "hue";
        static_configs = [
          { targets = [ "ogden-unencrypted:9366" ]; }
        ];
      }

      {
        job_name = "node";
        static_configs = [
          { targets = [
              "lord-nibbler-unencrypted:9100"
              "aarch64.nixos.community:9100"
              "packet-epyc-1:9100" "packet-t2-4:9100" "packet-t2a-1:9100"
              "packet-t2a-2:9100"
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
