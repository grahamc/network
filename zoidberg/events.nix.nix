{ secrets }:
{ pkgs, config, ... }:
let
  defaultVhostCfg = import ./default-vhost-config.nix;
  rabbit_tls_port = 5671;
  cert_dir = "${config.security.acme.directory}/events.nix.gsc.io";

  vhostPHPLocations = pkgs: root: {
    "/" = {
      index = "index.php index.html";

      extraConfig = ''
        try_files $uri $uri/ /index.php$is_args$args;
      '';
    };

    "~ \.php$" = {
      extraConfig = ''
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME ${root}/$fastcgi_script_name;
        include ${pkgs.nginx}/conf/fastcgi_params;
      '';
    };
  };

in {

    networking = {
      firewall = {
        allowedTCPPorts = [ 5671 15671 ];
      };

      extraHosts = ''
        127.0.0.1 zoidberg
      '';
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
