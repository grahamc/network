{ secrets }:
{ pkgs, config, ... }:
let
  defaultVhostCfg = import ./default-vhost-config.nix;
  rabbit_tls_port = 5671;
  cert_dir = "${config.security.acme.directory}/events.nix.gsc.io";
in {

    networking = {
      firewall = {
        allowedTCPPorts = [ 5671 ];
      };
    };

  security.acme.certs."events.nix.gsc.io" = {
    plugins = [ "cert.pem" "fullchain.pem" "full.pem" "key.pem" "account_key.json" ];
    group = "rabbitmq";
    allowKeysForGroup = true;
  };

  services = {
    nginx = {
      virtualHosts = {
        "events.nix.gsc.io" = defaultVhostCfg // {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            index = "index.html";
            root = pkgs.writeTextDir "index.html" "email me for creds: graham-at-grahamc-dot-com, gchristensen on irc";
          };
        };
      };
    };

    rabbitmq = {
      enable = true;
      cookie = secrets.rabbitmq.cookie;
      plugins = [ "rabbitmq_management" ];
      config = ''
        [
          {rabbit, [
             {ssl_listeners, [{"0.0.0.0", 5671}]},
             {ssl_options, [
                            {cacertfile,"${cert_dir}/fullchain.pem"},
                            {certfile,"${cert_dir}/cert.pem"},
                            {keyfile,"${cert_dir}/key.pem"},
                            {verify,verify_none},
                            {fail_if_no_peer_cert,false}]},
             {log_levels, [{connection, debug}]}
           ]},
           {rabbitmq_management, [{listener, [{port, 15672}]}]}
        ].
      '';
    };
  };

  # Delete after September 24 2017
  systemd.services.rabbitmq.environment.RABBITMQ_LOGS = "-";
  systemd.services.rabbitmq.environment.RABBITMQ_SASL_LOGS = "-";
  systemd.services.rabbitmq.environment.RABBITMQ_SERVER_START_ARGS = "";
}
