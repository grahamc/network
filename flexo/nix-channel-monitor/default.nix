{ secrets }:
{ pkgs, config, ... }:
{
  systemd.tmpfiles.rules = [
    "d ${config.services.nginx.virtualHosts."channels.nix.gsc.io".root} 0755 nix-channel-monitor nginx"
  ];
  services.nginx.virtualHosts."channels.nix.gsc.io" = {
    root = "/var/lib/nginx/nix-channel-monitor/monitor/public";
    enableACME = true;
    forceSSL = true;
    locations."/".extraConfig = ''
      autoindex on;
    '';
  };

  users.users.nix-channel-monitor = {
    description = "Nix Channel Monitor";
    home = "/var/lib/nix-channel-monitor";
    createHome = true;
    group = "nix-channel-monitor";
    uid = 400;
  };
  users.groups.nix-channel-monitor.gid = 400;

  systemd.services = {
    nix-channel-monitor = {
      after = [ "network.target" "network-online.target" ];
      wants = [ "network-online.target" ];
      path = with pkgs; [
        telnet
        git
        gawk
        curl
      ];

      serviceConfig = {
        User = "nix-channel-monitor";
        Group = "nix-channel-monitor";
        Type = "oneshot";
        PrivateTmp = true;
        WorkingDirectory = "/var/lib/nix-channel-monitor";
      };

      preStart = ''
        set -eux
        if [ ! -d /var/lib/nix-channel-monitor/git ]; then
          git clone https://github.com/nixos/nixpkgs-channels.git git
        fi
      '';

      script = let
        src = pkgs.runCommand "queue-monitor-src" {}
        ''
          mkdir queue-monitor
          cp ${./changes.sh} ./changes.sh
          sed -i 's#AMQPAPI#${secrets.rabbitmq.nixchannelmonitor}#' ./changes.sh
          cp -r ./changes.sh $out
        '';
      in ''
        ${src} /var/lib/nix-channel-monitor/git ${config.services.nginx.virtualHosts."channels.nix.gsc.io".root}
      '';
    };
  };

  systemd.timers = {
    run-nix-channel-monitor = {
      description = "Rerun the nix channel monitor";
      wantedBy = [ "timers.target" ];
      partOf = [ "nix-channel-monitor.service" ];
      enable = true;
      timerConfig = {
        OnCalendar = "*:0/5";
        Unit = "nix-channel-monitor.service";
        Persistent = "yes";
        AccuracySec = "1m";
        RandomizedDelaySec = "30s";
      };
    };
  };
}
