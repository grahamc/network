{ pkgs, config, ... }:
{
  systemd = {
    services = {
      everyaws = {
        after = [ "network.target" "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          (pkgs.python3.withPackages (ps: [ ps.tweepy ]))
        ];

        serviceConfig = {
          User = "grahamc";
          Group = "users";
          Type = "oneshot";
          PrivateTmp = true;
          WorkingDirectory = "/home/grahamc/everyaws";
        };

        script = ''
          ./tweet.sh
        '';
      };
    };

    timers = {
      everyaws = {
        description = "Announces a new AWS service";
        wantedBy = [ "timers.target" ];
        partOf = [ "everyaws.service" ];
        enable = true;
        timerConfig = {
          OnCalendar = "*:0/15";
          Unit = "everyaws.service";
          Persistent = "yes";
          AccuracySec = "1m";
          RandomizedDelaySec = "30s";
        };
      };
    };
  };
}
