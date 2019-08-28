{ pkgs, config, ... }:
{
  systemd = {
    services = {
      periodicreminder = {
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
          WorkingDirectory = "/home/grahamc/yrperiodicreminder";
        };

        script = ''
          ./tweet.sh
        '';
      };
    };

    timers = {
      periodicreminder = {
        description = "Remind people of important things of the past.";
        wantedBy = [ "timers.target" ];
        partOf = [ "periodicreminder.service" ];
        enable = true;
        timerConfig = {
          OnCalendar = "16,18,20,22:30";
          Unit = "periodicreminder.service";
          Persistent = "yes";
          RandomizedDelaySec = "30m";
        };
      };
    };
  };
}
