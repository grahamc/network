{ stdenv, python3Packages, makeWrapper }:
stdenv.mkDerivation {
  name = "learn";
  src = ./.;

  buildInputs = [
    makeWrapper
  ] ++ (with python3Packages; [ python flake8 ]);

  doCheck = true;
  checkPhase = ''
    flake8 ./learn.py
  '';

  installPhase = ''
    mkdir -p $out/bin/
    mv ./learn.py $out/bin/learn
  '';
}
