{ lib, ... }:
{
  hardware.enableAllFirmware = true;
  boot.initrd.availableKernelModules = [ "ahci" "ohci_pci" "ehci_pci" "pata_atiixp" "xhci_pci" "pata_jmicron" "usb_storage" "usbhid" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/80cfb641-6b26-4a80-825a-2a8af51b0fe2";
      fsType = "ext4";
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


  swapDevices = [ ];

  nix.maxJobs = lib.mkDefault 6;


  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only

  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "a207025c";
  services.zfs.autoScrub.enable = true;
}
