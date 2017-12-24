{ secrets }:
{ ... }:
{
  imports = [
    ./hardware.nix
    (import ./router.nix  { inherit secrets; })
    ./pxe-image.nix
  ];

  services.fail2ban = {
    enable = true;
  };


}
