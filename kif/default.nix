{ secrets }:
{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ../modules/wireguard.nix
    (import ./vault.nix { inherit secrets; })
    ./buildkite.nix
    #(import ./prometheus.nix { inherit secrets; })
    #./sdr.nix
    #(import ./dns.nix { inherit secrets; })
    #../../../NixOS/nixos-org-configurations/macs/host
    # possibly breaking r13y.com # (import ../../../andir/local-nix-cache/module.nix)
  ];

  services.openssh.enable = true;
  systemd.tmpfiles.rules = [''
    e /tmp/nix-build-* - - - 1d -
  ''];

  nix = {
      gc = {
        automatic = true;
        dates = "8:06";

        options = let
          freedGb = 300;
        in ''--max-freed "$((${toString freedGb} * 1024**3 - 1024 * $(df -P -k /nix/store | tail -n 1 | ${pkgs.gawk}/bin/awk '{ print $4 }')))"'';
      };
   };

  # Select internationalisation properties.
  i18n = {
    consoleFont = "Lat2-Terminus16";
    consoleKeyMap = "dvorak";
    defaultLocale = "en_US.UTF-8";
  };

  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
    emacs26-nox
    screen
  ];

  services.nginx = {
    enable = true;
    virtualHosts."plex.gsc.io" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:32400";
    };
    virtualHosts."plex.wg.gsc.io" = {
      # dns-01 validation?
      #enableACME = true;
      #forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:32400";
    };

  };

  networking.firewall.allowedTCPPorts = [
    80 # nginx -> plex
    443 # nginx -> plex

    # Plex: Found at https://github.com/NixOS/nixpkgs/blob/release-17.03/nixos/modules/services/misc/plex.nix#L156
    32400 3005 8324 32469
    9100 # Prometheus NodeExporter
  ];

  networking.firewall.allowedUDPPorts = [
    # Plex: Found at https://github.com/NixOS/nixpkgs/blob/release-17.03/nixos/modules/services/misc/plex.nix#L156
    1900 5353 32410 32412 32413 32414 # UDP
  ];


  users = {
    groups.writemedia = {};
    extraUsers = {
      root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINT2IAcpePtxrnk9XiXRRkInvvXm6X00mYFd3rpMSBNW root@Petunia"
      ];

      hydraexport = {
        isNormalUser = true; # not really, but need to be able to execute commands
        uid = 1004;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyyr/4fMKQ1fwa5DjFVIHQLchr4EKcOWEI++gYBTbWF root@haumea"
        ];
      };
      flexoexport = {
        isNormalUser = true; # not really, but need to be able to execute commands
        uid = 1005;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINsBEaKyvlXvVGjMT7LEhYs87kVNiTpeVtWNtjnElSSg"
        ];
      };
    };
  };

  # Plex
  services.plex = {
    enable = true;
    package = pkgs.plex.overrideAttrs (x: let
        # see https://www.plex.tv/media-server-downloads/ for 64bit rpm
        version = "1.18.6.2368-97add474d";
        sha1 = "9df823ae360c5c9508c4ebefa417df66796b353c";
      in {
        name = "plex-${version}";
        src = pkgs.fetchurl {
          url = "https://downloads.plex.tv/plex-media-server-new/${version}/redhat/plexmediaserver-${version}.x86_64.rpm";
          # url = "https://downloads.plex.tv/plex-media-server-new/${version}/plexmediaserver-${version}.x86_64.rpm";
          inherit sha1;
        };
      }
    );
  };
}
