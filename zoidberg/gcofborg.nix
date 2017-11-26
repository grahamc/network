{ pkgs, ... }:
let
  src = pkgs.callPackage ./gcofborgpkg.nix {};

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
        php ${src}/${name}.php
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
in {
  users.users.gc-of-borg = {
    description = "GC Of Borg Workers";
    home = "/var/lib/gc-of-borg";
    createHome = true;
    group = "gc-of-borg";
    uid = 402;
  };
  users.groups.gc-of-borg.gid = 402;

  systemd = {
    services =
      (rustborgservice "github-comment-filter" ./../../ofborg/ofborg/target/debug/github-comment-filter ./../../ofborg/config.prod.json) //
      (rustborgservice "builder" ./../../ofborg/ofborg/target/debug/builder ./../../ofborg/config.prod.json) //
      (rustborgservice "mass-rebuilder" ./../../ofborg/ofborg/target/debug/mass-rebuilder ./../../ofborg/config.prod.json) //

      (phpborgservice "poster") //
      (phpborgservice "mass-rebuild-filter") //
      {};
  };
}
