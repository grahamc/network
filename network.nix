let
  secrets = import ./secrets.nix;
in {
  zoidberg = { ... }: {
    imports = [
      (import ./zoidberg { inherit secrets; })
    ];
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


  ofborg-evaluator-0 = { ... }: {
    deployment = {
      targetHost = "195.201.26.67";
    };

    imports = [
      (import ./ofborg-evaluator-0 { inherit secrets; })
    ];
  };
}
