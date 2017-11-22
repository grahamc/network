{ runCommand }:
runCommand "ofborg" {
  src = builtins.filterSource
    (path: type: !(
         (type == "directory" && baseNameOf path == "ofborg")
      || (type == "directory" && baseNameOf path == ".git")
    ))
    ./../../ofborg;
} ''
  cp -r $src ./ofborg
  chmod -R u+w ./ofborg
  cd ofborg
  ls -la
  cd ..
  mv ofborg $out
''
