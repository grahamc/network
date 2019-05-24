let
  secrets = import ./secrets.nix;
in {
  defaults = {
    about = import ./intake;
  };
  network.enableRollback = true;

  zoidberg = { ... }: {
    imports = [
      (import ./zoidberg { inherit secrets; })
    ];
    boot.loader.grub.memtest86.enable = true;
  };

  flexo = { ... }: {
    deployment = {
      targetHost = "147.75.105.137";
    };

    imports = [
      (import ./flexo { inherit secrets; })
    ];
    boot.loader.grub.memtest86.enable = true;
  };

  lord-nibbler = { ... }: {
    deployment = {
      targetHost = "10.5.3.1";
    };

    imports = [
      (import ./lord-nibbler { inherit secrets; })
    ];
  };

  ogden = { ... }: {
    deployment = {
      targetHost = "10.5.3.105"; # if true then "10.5.3.1" else "67.246.21.246";
    };

    imports = [
      (import ./ogden { inherit secrets; })
    ];
  };
}
