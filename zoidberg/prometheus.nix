{ secrets }:
{ pkgs, ... }:
{
  services.grafana = {
    enable = true;
  };

  services.prometheus = {
    enable = true;

    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          { targets = [ "zoidberg:9090" ]; }
        ];
      }

      {
        job_name = "ofborg-workers";
        honor_labels = true;
        static_configs = [
          { targets = [ "zoidberg:9898" ]; }
        ];
      }

      {
        job_name = "node";
        static_configs = [
          { targets = [ "zoidberg:9100" "ogden:9100"
           ]; }
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
  };
}
