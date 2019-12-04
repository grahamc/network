{ pkgs, ... }:
let
  src = import ./../../ircbot/ofborg {};
  githubgateway = import ./../../../samueldr/github-to-irc/default.nix { inherit pkgs; };
  # openssl 1.0 -> 1.1 in 19.03 -> 19.09 busted this service
  # pijulnestgateway = pkgs.callPackage ../../../../nest.pijul.com/grahamc/nest-to-irc { };

  ircservice = name: bin: cfg: {
    "ircbot-${name}" = {
      enable = true;
      after = [ "network.target" "network-online.target" "rabbitmq.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = "ofborg-irc";
        Group = "ofborg-irc";
        PrivateTmp = true;
        Restart = "always";
      };

      script = ''
        export RUST_BACKTRACE=1
        ${bin} ${cfg}
      '';
    };
  };

in {
  users.users.ofborg-irc = {
    description = "GC Of Borg IRC";
    home = "/var/empty";
    group = "ofborg-irc";
    uid = 403;
  };
  users.groups.ofborg-irc.gid = 403;


  systemd = {
    services =
      (ircservice "gateway"
        "${src.ircbot}/bin/gateway"
        ./../../ircbot/ofborg/config.irc.json) //
      (ircservice "github-to-irc"
        "${githubgateway}/bin/github-to-irc"
        "${./../../ircbot/ofborg/config.irc.json}") //
      #(ircservice "pijul-nest-to-irc"
      #  "${pijulnestgateway}/bin/nest-to-irc"
      #  "${../../../../nest.pijul.com/grahamc/nest-to-irc/url}") //
      {};

  };
}
