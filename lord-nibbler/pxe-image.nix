{ config, pkgs, lib, ... }:
let
   nixpkgs_path = ./../../nixpkgs; # pkgs.path;

    mkNetboot = config: let
      config_evaled = import "${nixpkgs_path}/nixos/lib/eval-config.nix" config;
      build = config_evaled.config.system.build;
      kernelTarget = config_evaled.pkgs.stdenv.platform.kernelTarget;
    in
      pkgs.symlinkJoin {
        name="netboot";
        paths=[
          build.netbootRamdisk
          build.kernel
          build.netbootIpxeScript
        ];
        postBuild = ''
          mkdir -p $out/nix-support
          echo "file ${kernelTarget} $out/${kernelTarget}" >> $out/nix-support/hydra-build-products
          echo "file initrd $out/initrd" >> $out/nix-support/hydra-build-products
          echo "file ipxe $out/netboot.ipxe" >> $out/nix-support/hydra-build-products
        '';
      };
in {
  services.nginx = {
    enable = true;
    virtualHosts.default = {
      default = true;
      root = config.services.tftpd.path;
    };

  };

  services.tftpd = let
    netboot_x86_64 = mkNetboot {
      system = "x86_64-linux";
      modules = [
        "${nixpkgs_path}/nixos/modules/installer/netboot/netboot-minimal.nix"
         { boot.kernelParams = [ "console=ttyS0,115200n8" ]; }
      ];
    };

    netboot_aarch64 = mkNetboot {
      system = "aarch64-linux";
      modules = [
        "${nixpkgs_path}/nixos/modules/installer/netboot/netboot-minimal.nix"
         { boot.kernelParams = [ "console=ttyS0,115200n8" ]; }
      ];
    };
   in {
    enable = true;
        #ln -s ${netboot_x86_64} $out/nixos-x86_64
        #ln -s ${netboot_aarch64} $out/nixos-aarch64

    path = pkgs.runCommand "dhcp-pxe-root" {}
      ''
        mkdir $out
        ln -s ${pkgs.ipxe} $out/ipxe
      '';
  };
}
