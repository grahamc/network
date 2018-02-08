{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.services.standard;
  secrets = import ../../secrets.nix;
in {
  config = {
    nixpkgs = {
      config = {
        allowUnfree = true;
        packageOverrides = pkgs: {
          prometheus-node-exporter = pkgs.prometheus-node-exporter.overrideAttrs (x: {
            # Update from 17.09's 0.14.0 because it lacked CPU metric support
            src = pkgs.fetchFromGitHub {
              rev = "v0.15.0";
              owner = "prometheus";
              repo = "node_exporter";
              sha256 = "0v1m6m9fmlw66s9v50y2rfr5kbpb9mxbwpcab4cmgcjs1y7wcn49";
            };
          });
        };
      };
    };

    services.openssh = {
      enable = true;
      passwordAuthentication = false;
    };

    networking = {
      extraHosts = ''
        # 2604:6000:e6cf:1901::1 lord-nibbler
        2604:6000:e6c2:f501:8e89:a5ff:fe10:53f0 ogden
        195.201.26.67 ofborg-evaluator-0
      '';

      firewall = {
        enable = true;
        allowedTCPPorts = [ 22 ];
      };
    };

    users = {
      mutableUsers = false;
      users = {
        root.openssh.authorizedKeys.keyFiles = [
          secrets.root.keys
        ];

        grahamc = {
          isNormalUser = true;
          uid = 1000;
          extraGroups = [ "wheel" ];
          createHome = true;
          home = "/home/grahamc";
          hashedPassword = secrets.grahamc.password;
          openssh.authorizedKeys.keyFiles = [
            secrets.grahamc.keys
          ];
        };
      };
    };

    nix = {
      useSandbox = true;

      nixPath = [
        # Ruin the config so we don't accidentally run
        # nixos-rebuild switch on the host
        (let
          cfg = pkgs.writeText "configuration.nix"
            ''
              assert builtins.trace "Hey dummy, you're on your server! Use NixOps!" false;
              {}
            '';
         in "nixos-config=${cfg}")

         # Copy the channel version from the deploy host to the target
         "nixpkgs=/run/current-system/nixpkgs"
      ];
    };

    system.extraSystemBuilderCmds = ''
      ln -sv ${pkgs.path} $out/nixpkgs
    '';
    environment.etc.host-nix-channel.source = pkgs.path;

    services.prometheus.nodeExporter = {
      enable = true;
      enabledCollectors = [
        # "cpu" # broken?
        "bonding" "systemd" "diskstats" "filesystem" "netstat" "meminfo"
        "textfile"
      ];
      extraFlags = [
        "--collector.textfile.directory=/var/lib/prometheus-node-exporter-text-files"
        ""
      ];
    };

    system.activationScripts.node-exporter-system-version = ''
      mkdir -pm 0775 /var/lib/prometheus-node-exporter-text-files
      (
        cd /var/lib/prometheus-node-exporter-text-files
        (
          echo -n "system_version ";
          readlink /nix/var/nix/profiles/system | cut -d- -f2
        ) > system-version.prom.next
        mv system-version.prom.next system-version.prom
      )

    '';

    # Ugh, delete this garbage!
    systemd.services.prometheus-node-exporter.script = lib.mkForce (let
        cfg = config.services.prometheus.nodeExporter;
      in ''
        exec ${pkgs.prometheus-node-exporter}/bin/node_exporter \
          ${lib.concatMapStringsSep " " (x: "--collector." + x) cfg.enabledCollectors} \
          --web.listen-address ${cfg.listenAddress}:${toString cfg.port} \
          ${lib.concatStringsSep " \\\n  " cfg.extraFlags}
      '');
  };
}
