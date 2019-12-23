{ secrets }:
{ pkgs, config, ... }:
let
  rabbit_tls_port = 5671;
  cert_dir = "/var/lib/acme/flexo.gsc.io";
in {
  networking = {
    firewall = {
      allowedTCPPorts = [ 80 443 5671 15671 ];
      extraCommands = ''
        # epmd
        ip46tables -A nixos-fw -i wg0 -p tcp \
          --dport 4369 -j nixos-fw-accept

        # inter-node chat
        ip46tables -A nixos-fw -i wg0 -p tcp \
          --dport 25672 -j nixos-fw-accept

        # CLI chat
        ip46tables -A nixos-fw -i wg0 -p tcp \
          --dport 35672:35682 -j nixos-fw-accept

        # web interface
        ip46tables -A nixos-fw -i wg0 -p tcp \
          --dport 15672 -j nixos-fw-accept
      '';
    };
  };

  security.acme.certs."flexo.gsc.io" = {
    extraDomains = {
      "events.nix.gsc.io" = null;
    };
    plugins = [ "cert.pem" "fullchain.pem" "full.pem" "key.pem" "account_key.json" "account_reg.json" ];
    group = "rabbitmq";
    allowKeysForGroup = true;
  };

  services = {
    nginx = {
      virtualHosts = {
        "flexo.gsc.io" = {
          enableACME = true;
          forceSSL = true;
        };
      };
    };

    rabbitmq = {
      enable = true;
      cookie = secrets.rabbitmq.cookie;
      plugins = [ "rabbitmq_management" "rabbitmq_web_stomp" "rabbitmq_shovel" "rabbitmq_shovel_management" ];
      config = ''
        [
          {rabbit, [
             {tcp_listen_options, [
                     {keepalive, true}]},
             {heartbeat, 10},
             {ssl_listeners, [{"::", 5671}]},
             {ssl_options, [
                            {cacertfile,"${cert_dir}/fullchain.pem"},
                            {certfile,"${cert_dir}/cert.pem"},
                            {keyfile,"${cert_dir}/key.pem"},
                            {verify,verify_none},
                            {fail_if_no_peer_cert,false}]},
             {log_levels, [{connection, debug}]}
           ]},
           {rabbitmq_management, [{listener, [{port, 15672}]}]},
           {rabbitmq_web_stomp,
                    [{ssl_config, [{port,       15671},
                     {backlog,    1024},
                     {cacertfile,"${cert_dir}/fullchain.pem"},
                     {certfile,"${cert_dir}/cert.pem"},
                     {keyfile,"${cert_dir}/key.pem"}
                ]}]}
        ].
      '';
    };
  };
}
