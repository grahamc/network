{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.services.ofborg;

  src = import ./../../ofborg {};

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
        RestartSec = "10s";
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

  rustborgservice = name: bin: conf: {
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
        RestartSec = "10s";
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
        ${bin} ${conf}
      '';
    };
  };

  ifAdministrative = service: if cfg.enable_administrative
    then service
    else {};

  ifEvaluator = service: if cfg.enable_evaluator
    then service
    else {};

  ifBuilder = service: if cfg.enable_builder
    then service
    else {};

in {
  options = {
    services.ofborg = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };

      enable_administrative = mkOption {
        type = types.bool;
        default = false;
      };

      enable_evaluator = mkOption {
        type = types.bool;
        default = false;
      };

      enable_builder = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  config = mkIf cfg.enable rec {
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
        (ifBuilder (rustborgservice "builder"
          "${src.ofborg.rs}/bin/builder"
          ./../../ofborg/config.prod.json)) //

        (ifEvaluator (rustborgservice "mass-rebuilder"
          "${src.ofborg.rs}/bin/mass_rebuilder"
          ./../../ofborg/config.prod.json)) //

        (ifAdministrative (rustborgservice "github-comment-poster"
          "${src.ofborg.rs}/bin/github_comment_poster"
           ./../../ofborg/config.prod.json)) //

        (ifAdministrative (rustborgservice "github-comment-filter"
          "${src.ofborg.rs}/bin/github_comment_filter"
           ./../../ofborg/config.prod.json)) //
        (ifAdministrative (rustborgservice "log-message-collector"
          "${src.ofborg.rs}/bin/log_message_collector"
           ./../../ofborg/config.prod.json)) //
        (ifAdministrative (phpborgservice "mass-rebuild-filter")) //

        {};
    };
  };
}
