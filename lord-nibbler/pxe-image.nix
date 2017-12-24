{ config, pkgs, ... }:
{
  services.nginx = {
    enable = true;
    virtualHosts.default = {
      default = true;
      root = config.services.tftpd.path;
    };

  };

  services.tftpd = let
    netboot = let build = (import <nixpkgs/nixos/lib/eval-config.nix> {
        system = "x86_64-linux";
        modules = [
          <nixpkgs/nixos/modules/installer/netboot/netboot-minimal.nix>
           { boot.kernelParams = [ "console=ttyS0,115200n8" ]; }
        ];
      }).config.system.build;
    in pkgs.symlinkJoin {
      name="netboot";
      paths=[
        build.netbootRamdisk
        build.kernel
        build.netbootIpxeScript
      ];
      postBuild = ''
        mkdir -p $out/nix-support
        echo "file bzImage $out/bzImage" >> $out/nix-support/hydra-build-products
        echo "file initrd $out/initrd" >> $out/nix-support/hydra-build-products
        echo "file ipxe $out/netboot.ipxe" >> $out/nix-support/hydra-build-products
      '';
    };
   in {
    enable = true;
    path = pkgs.runCommand "dhcp-pxe-root" {}
      ''
        mkdir $out
        ln -s ${netboot} $out/nixos
        ln -s ${pkgs.ipxe} $out/ipxe
      '';
  };
}
