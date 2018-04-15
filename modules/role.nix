{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.terraform;

  isRole = role: builtins.elem role cfg.roles.enabled;
in {
  options = {
    terraform = {
      roles.enabled = mkOption {
        type = types.listOf types.string;
        default = [];
      };

      name = mkOption {
        type = types.string;
      };

      idx = mkOption {
        type = types.int;
      };
    };
  };

  config = mkIf (isRole "evaluator") rec {


    boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "sd_mod" "sr_mod" ];
    boot.kernelModules = [ ];
    boot.extraModulePackages = [ ];

    fileSystems."/" =
      { device = "/dev/disk/by-uuid/nixos";
        fsType = "ext4";
      };

    swapDevices = [ ];

    nix.maxJobs = lib.mkDefault 2;
    boot.loader.grub.enable = true;
    boot.loader.grub.version = 2;
    boot.loader.grub.device = "/dev/sda";

    networking.firewall.allowedTCPPorts = [ 9100 ];

    services = {
      ofborg = {
        enable = true;
        enable_evaluator = true;
      };
    };

    nix.gc = {
      automatic = true;
      dates = "*:0/15";

      options = let
        freedGb = 60;
      in ''--max-freed "$((${toString freedGb} * 1024**3 - 1024 * $(df -P -k /nix/store | tail -n 1 | ${pkgs.gawk}/bin/awk '{ print $4 }')))"'';
    };
  };
}
