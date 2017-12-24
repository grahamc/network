{ secrets }:
{ pkgs, ... }:
{
  services.grafana = {
    enable = true;
  };

  services.prometheus = {
    enable = true;

    alertmanagerURL = [ "http://127.0.0.1:9093" ];
    rules = [
      ''
        ALERT StalledEvaluator
        IF (ofborg_queue_evaluator_waiting - ofborg_queue_evaluator_in_progress) >= ofborg_queue_evaluator_waiting
        FOR 5m
        LABELS {
          severity="page"
        }
      ''
    ];


    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          { targets = [ "localhost:9090" ]; }
        ];
      }

      {
        job_name = "node";
        static_configs = [
          { targets = [ "localhost:9100" ]; }
        ];
      }

      {
        job_name = "ofborg-queue";
        metrics_path = "/prometheus.php";
        scheme = "https";
        static_configs = [
          {
            targets = [ "events.nix.gsc.io" ];
          }
        ];
      }
    ];

    nodeExporter = {
      enable = true;
      enabledCollectors = [
        "bonding" "systemd" "diskstats" "filesystem" "netstat" "meminfo"
      ];
    };

    alertmanager = {
      enable = true;
      configuration = {
        global = {};
        route = {
          receiver = "default_receiver";
          group_by = ["cluster" "alertname"];
        };

        receivers = [
          {
            name = "default_receiver";
            pushover_configs = [
              {
                user_key = secrets.pushover.user_key;
                token = secrets.pushover.app_token;
              }
            ];
          }
        ];
      };
    };
  };
}
