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
        IF ofborg_queue_evaluator_waiting > 0 and ofborg_queue_evaluator_in_progress == 0
        FOR 5m
        LABELS {
          severity="page"
        }

        ALERT StalledBuilder
        IF ofborg_queue_builder_waiting > 0 and ofborg_queue_builder_in_progress == 0
        FOR 5m
        LABELS {
          severity="page"
        }

        ALERT FreeInodes4HrsAway
        IF predict_linear(node_filesystem_files_free{mountpoint="/"}[1h], 4   * 3600) <= 0
        FOR 5m
        LABELS {
          severity="page"
        }

        ALERT FreeSpace4HrsAway
        IF predict_linear(node_filesystem_free{mountpoint="/"}[1h], 4 * 3600) <= 0
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
          { targets = [ "zoidberg:9090" ]; }
        ];
      }

      {
        job_name = "node";
        static_configs = [
          { targets = [ "zoidberg:9100" "router:9100" ]; }
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
