{ pkgs, ... }:
let
  src = import ./gcofborgpkg.nix;
  githubgateway = import ./../../github-to-irc/default.nix { inherit pkgs; };

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
        ./../../ofborg/config.irc.json) //
      (ircservice "factoids"
        "${src.ircbot}/bin/factoids"
        "${./../../ofborg/config.irc.json} ${./../../ofborg/factoids.toml}") //
      (ircservice "github-to-irc"
        "${githubgateway}/bin/github-to-irc"
        "${./../../ofborg/config.irc.json}") //
      {};

  };
}
