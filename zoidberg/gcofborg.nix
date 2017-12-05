{ pkgs, ... }:
let
  src = import ./gcofborgpkg.nix;

  phpborgservice = name: {
    "grahamcofborg-${name}" = {
      enable = true;
      after = [ "network.target" "network-online.target" "rabbitmq.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [
        nix
        git
        php
        curl
        bash
      ];

      serviceConfig = {
        User = "gc-of-borg";
        Group = "gc-of-borg";
        PrivateTmp = true;
        WorkingDirectory = "/var/lib/gc-of-borg";
        Restart = "always";
      };

      preStart = ''
        mkdir -p ./.nix-test
      '';

      script = ''
        export HOME=/var/lib/gc-of-borg;
        export NIX_REMOTE=daemon;
        export NIX_PATH=nixpkgs=/run/current-system/nixpkgs;
        git config --global user.email "graham+cofborg@grahamc.com"
        git config --global user.name "GrahamCOfBorg"
        php ${src.ofborg.php}/${name}.php
      '';
    };
  };


  rustborgservice = name: bin: cfg: {
    "grahamcofborg-${name}" = {
      enable = true;
      after = [ "network.target" "network-online.target" "rabbitmq.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [
        nix
        git
        curl
        bash
      ];

      serviceConfig = {
        User = "gc-of-borg";
        Group = "gc-of-borg";
        PrivateTmp = true;
        WorkingDirectory = "/var/lib/gc-of-borg";
        Restart = "always";
      };

      preStart = ''
        mkdir -p ./.nix-test
      '';

      script = ''
        export HOME=/var/lib/gc-of-borg;
        export NIX_REMOTE=daemon;
        export NIX_PATH=nixpkgs=/run/current-system/nixpkgs;
        git config --global user.email "graham+cofborg@grahamc.com"
        git config --global user.name "GrahamCOfBorg"
        export RUST_BACKTRACE=1
        ${bin} ${cfg}
      '';
    };
  };


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
  users.users.gc-of-borg = {
    description = "GC Of Borg Workers";
    home = "/var/lib/gc-of-borg";
    createHome = true;
    group = "gc-of-borg";
    uid = 402;
  };
  users.groups.gc-of-borg.gid = 402;

  users.users.ofborg-irc = {
    description = "GC Of Borg IRC";
    home = "/var/empty";
    group = "ofborg-irc";
    uid = 403;
  };
  users.groups.ofborg-irc.gid = 403;


  systemd = {
    services =
      (rustborgservice "github-comment-filter"
        "${src.ofborg.rs}/bin/github_comment_filter"
         ./../../ofborg/config.prod.json) //
      (rustborgservice "builder"
        "${src.ofborg.rs}/bin/builder"
        ./../../ofborg/config.prod.json) //

      (rustborgservice "mass-rebuilder"
        "${src.ofborg.rs}/bin/mass_rebuilder"
        ./../../ofborg/config.prod.json) //

      (phpborgservice "poster") //
      (phpborgservice "mass-rebuild-filter") //

      (ircservice "gateway"
        "${src.ircbot}/bin/gateway"
        ./../../ofborg/config.irc.json) //

      {};
  };
}
