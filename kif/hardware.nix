{ pkgs, ... }:
{
  boot.initrd.availableKernelModules = [ "mpt3sas" "xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];
  boot.kernelParams = [ "console=tty1,115200n8" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;

  fileSystems."/" =
    { device = "hpool/local/root";
      fsType = "zfs";
    };
  fileSystems."/mnt" =
    { device = "/dev/sdh1";
      fsType = "ext4";
    };
  fileSystems."/nix" =
    { device = "hpool/local/nix";
      fsType = "zfs";
    };
  fileSystems."/boot" =
    { device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
    };

  fileSystems."/home/emilyc/timemachine" =
    { device = "rpool/time-machine/emily";
      fsType = "zfs";
      options = [ "nofail" ];
    };
  fileSystems."/home/grahamc/timemachine" =
    { device = "rpool/time-machine/graham";
      fsType = "zfs";
      options = [ "nofail" ];
    };
  fileSystems."/home/kchristensen/storage" =
    { device = "rpool/kyle/storage";
      fsType = "zfs";
      options = [ "nofail" ];
    };
  fileSystems."/media" =
    { device = "rpool/media/plex";
      fsType = "zfs";
      options = [ "nofail" ];
    };


  networking.hostId = "2016154b";
  swapDevices = [ ];
  boot.loader.systemd-boot.enable = true;
  nix.maxJobs = 12;
  services.zfs.autoScrub.enable = true;
}
